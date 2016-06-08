import Foundation
import RealmSwift
import CloudKit
import PSOperations

class PushLocalChangesOperation: Operation {
    
    let zoneID: CKRecordZoneID
    var recordsToSave: [CKRecord]?
    var recordIDsToDelete: [CKRecordID]?
    
    let delayOperationQueue = OperationQueue()
    let maximumRetryAttempts: Int
    var retryAttempts: Int = 0
    
    let objectClass: RealmCloudObject.Type
    
    init(zoneID: CKRecordZoneID, objectClass: RealmCloudObject.Type, maximumRetryAttempts: Int = 3) {
        self.zoneID = zoneID
        self.objectClass = objectClass
        self.maximumRetryAttempts = maximumRetryAttempts
        
        super.init()
        name = "Push Local Changes"
    }
    
    override func execute() {
        print("\(self.name!) started")
        
        // Query records
        
        let realm = try! Realm()
        
        // FIXME: Unsafe realm casting
        let locallyModifiedObjects = realm.objects(self.objectClass as! Object.Type)
            .filter("isLocallyModified == true")
        let locallyDeletedObjects = realm.objects(self.objectClass as! Object.Type)
            .filter("isLocallyDeleted == true")
        
        self.recordsToSave = locallyModifiedObjects.map {
            ($0 as! RealmCloudObject).toRecord()
        }
        self.recordIDsToDelete = locallyDeletedObjects.map {
            CKRecordID(recordName: ($0 as! RealmCloudObject).id )
        }
        
        modifyRecords(self.recordsToSave, recordIDsToDelete: self.recordIDsToDelete) {
            (nsError) in
            self.finishWithError(nsError)
        }
    }
    
    func modifyRecords(recordsToSave: [CKRecord]?,
                       recordIDsToDelete: [CKRecordID]?,
                       completionHandler: (NSError!) -> ()) {
        
        let modifyOperation = CKModifyRecordsOperation(
            recordsToSave: recordsToSave,
            recordIDsToDelete: recordIDsToDelete)
        
        modifyOperation.modifyRecordsCompletionBlock = {
            (savedRecords, deletedRecordIDs, nsError) -> Void in
            
            if let error = nsError {
                
                self.handleCloudKitPushError(
                    savedRecords,
                    deletedRecordIDs: deletedRecordIDs,
                    error: error,
                    completionHandler: completionHandler)
                
            } else {
                
                do {
                    // Update local modified flag
                    if let savedRecords = savedRecords {
                        for record in savedRecords {
                            // FIXME: Unsafe realm casting
                            try setModified(record.recordID.recordName,
                                            type: self.objectClass as! Object.Type,
                                            value: false)
                        }
                    }
                    
                    if let recordIDsToDelete = recordIDsToDelete {
                        for recordID in recordIDsToDelete {
                            try deleteLocalRecord(recordID, objectClass: self.objectClass)
                        }
                    }
                    
                } catch let realmError as NSError {
                    self.finishWithError(realmError)
                }
                
                completionHandler(nsError)
            }
        }
        
        modifyOperation.start()
    }
    
    // MARK: - Error Handling
    
    /**
     Implement custom logic here for handling CloudKit push errors.
     */
    func handleCloudKitPushError(
        savedRecords: [CKRecord]?,
        deletedRecordIDs: [CKRecordID]?,
        error: NSError,
        completionHandler: (NSError!) -> ()) {
        
        let ckErrorCode: CKErrorCode = CKErrorCode(rawValue: error.code)!
        
        switch ckErrorCode {
            
        case .PartialFailure:
            self.resolvePushConflictsAndRetry(
                savedRecords,
                deletedRecordIDs: deletedRecordIDs,
                error: error,
                completionHandler: completionHandler)
            
        case .LimitExceeded:
            self.splitModifyOperation(error, completionHandler: completionHandler)
            
        case .ZoneBusy, .RequestRateLimited, .ServiceUnavailable, .NetworkFailure, .NetworkUnavailable, .ResultsTruncated:
            // Retry necessary
            retryPush(error,
                      retryAfter: parseRetryTime(error),
                      completionHandler: completionHandler)
            
        case .BadDatabase, .InternalError, .BadContainer, .MissingEntitlement,
             .ConstraintViolation, .IncompatibleVersion, .AssetFileNotFound,
             .AssetFileModified, .InvalidArguments, .UnknownItem,
             .PermissionFailure, .ServerRejectedRequest:
            // Developer issue
            completionHandler(error)
            
        case .QuotaExceeded, .OperationCancelled:
            // User issue. Provide alert.
            completionHandler(error)
            
        case .BatchRequestFailed, .ServerRecordChanged:
            // Not possible for push operation (I think) only possible for
            // individual records within the userInfo dictionary of a PartialFailure
            completionHandler(error)
            
        case .NotAuthenticated:
            // Handled as condition of SyncOperation
            // TODO: add logic to retry entire operation
            completionHandler(error)
            
        case .ZoneNotFound, .UserDeletedZone:
            // Handled in PrepareZoneOperation.
            // TODO: add logic to retry entire operation
            completionHandler(error)
            
        case .ChangeTokenExpired:
            // TODO: Determine correct handling
            completionHandler(error)
        }
    }
    
    /**
     In the case of a .LimitExceeded error split the CKModifyOperation in half. For simplicity,
     also split the save and delete operations.
     */
    func splitModifyOperation(error: NSError, completionHandler: (NSError!) -> ()) {
        
        if let recordsToSave = self.recordsToSave {
            
            if recordsToSave.count > 0 {
                print("Receiving CKErrorLimitExceeded with <= 1 records.")
                
                let recordsToSaveLeft = Array(recordsToSave.prefixUpTo(recordsToSave.count/2))
                let recordsToSaveRight = Array(recordsToSave.suffixFrom(recordsToSave.count/2))
                
                self.modifyRecords(recordsToSaveLeft,
                                   recordIDsToDelete: nil,
                                   completionHandler: completionHandler)
                
                self.modifyRecords(recordsToSaveRight,
                                   recordIDsToDelete: nil,
                                   completionHandler: completionHandler)
            }
        }
        
        if let recordIDsToDelete = self.recordIDsToDelete {
            
            if recordIDsToDelete.count > 0 {
                
                let recordIDsToDeleteLeft = Array(recordIDsToDelete.prefixUpTo(recordIDsToDelete.count/2))
                let recordIDsToDeleteRight = Array(recordIDsToDelete.suffixFrom(recordIDsToDelete.count/2))
                
                self.modifyRecords(nil,
                                   recordIDsToDelete: recordIDsToDeleteLeft,
                                   completionHandler: completionHandler)
                
                self.modifyRecords(nil,
                                   recordIDsToDelete: recordIDsToDeleteRight,
                                   completionHandler: completionHandler)
            }
        }
    }
    
    func resolvePushConflictsAndRetry(savedRecords: [CKRecord]?,
                                      deletedRecordIDs: [CKRecordID]?,
                                      error: NSError,
                                      completionHandler: (NSError!) -> ()) {
        
        let adjustedRecords = resolveConflicts(error,
                                               completionHandler: completionHandler,
                                               resolver: overwriteFromClient)
        
        modifyRecords(adjustedRecords, recordIDsToDelete: deletedRecordIDs, completionHandler: completionHandler)
    }
    
    // MARK: - Retry
    
    // Wait a default of 3 seconds
    func parseRetryTime(error: NSError) -> Double {
        var retrySecondsDouble: Double = 3
        if let retrySecondsString = error.userInfo[CKErrorRetryAfterKey] as? String {
            retrySecondsDouble = Double(retrySecondsString)!
        }
        return retrySecondsDouble
    }
    
    /**
     After `maximumRetryAttempts` this function will return an error.
     */
    func retryPush(error: NSError, retryAfter: Double, completionHandler: (NSError!) -> ()) {
        
        if self.retryAttempts < self.maximumRetryAttempts {
            self.retryAttempts += 1
            
            let delayOperation = DelayOperation(interval: retryAfter)
            delayOperation.completionBlock = {
                
                // Use the same records/recordIDs we initially tried to modify
                // the on the server in this operation.
                self.modifyRecords(self.recordsToSave,
                                   recordIDsToDelete: self.recordIDsToDelete,
                                   completionHandler: completionHandler)
            }
            
            delayOperationQueue.addOperation(delayOperation)
            
        } else {
            completionHandler(error)
        }
    }
}
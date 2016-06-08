import Foundation
import CloudKit
import RealmSwift

/**
    A simple Note containing text.
 
    Notes:
    - ckSystemFields is updated each time this note is synced with CloudKit 
 
    When modifying this class, ensure each of the following three sections
    are updated.
    S1. Define class fields.
    S2. Add desired class fields to the CKRecord in toRecord().
    S3. Replace custom class name in saveSystemFields() function.
 
 */
class Note: Object, RealmCloudObject {
    
    // S1: Define class fields.
    dynamic var text = ""
    dynamic var dateModified = NSDate()
    
    // All properties and functions below are required for RealmCloud
    
    dynamic var id = NSUUID().UUIDString
    dynamic var isLocallyModified = false
    dynamic var isLocallyDeleted = false
    dynamic var ckSystemFields: NSData? = nil
    
    override static func primaryKey() -> String? {
        return "id"
    }
    
    /**
        Create a CKRecord from the data contained in this object.
     */
    func toRecord() -> CKRecord {
        var record: CKRecord!
        
        // Note has been saved in cloud before
        if let localData = self.ckSystemFields {
            record = recordFromLocalData(localData)
        }
        
        // Note has never been saved to cloud.
        // - CKRecordID is created locally.
        // - CKRecordID is persisted locally, and will be updated with reponse
        //   from CloudKit after uploading.
        if record == nil {
            
            // Set cloudkit recordID using realm primary key. This way we can
            // update this record easily in the future.
            let recordID = CKRecordID(recordName: self.id, zoneID: zoneID)
            record = CKRecord(recordType: Constants.RecordType, recordID: recordID)
            saveSystemFields(record)
        }
        
        // S2: Add desired class fields to the CKRecord in toRecord().
        record["text"] = self.text
        record["dateModified"] = self.dateModified
        
        return record
    }
    
    /**
        Save CloudKit system fields on the local Realm record.
     */
    // TODO: This function should throw an error
    func saveSystemFields(record: CKRecord) {
//        dispatch_async(dispatch_queue_create("background", nil)) {
            let realm = try! Realm()
            let id = record.recordID.recordName
            
            do {
                try realm.write {
                    print("Saving system fields for: \(id) \n\twith change tag: \(record.recordChangeTag)")
                    
                    // S3. Replace custom class name in saveSystemFields() function.
                    realm.create(Note.self,
                        value: [
                            "id": id,
                            "ckSystemFields": recordToLocalData(record)
                        ],
                        update: true)
                }
            } catch let error as NSError {
                print(error)
            }
//        }
    }
}

/**
 Change a local record.
 
 - Checks local database to see if local record exists
 - If local record does not exist, create it
 - More difficult cases should be handled by CKModifyRecordsOperation, but still need to be checked here
 
 - throws: An `NSError` if saving results in an error.
 */
public func changeLocalRecord(record: CKRecord, objectClass: RealmCloudObject.Type) throws {
    print("changed local record")
    let realm = try! Realm()
    let id = record.recordID.recordName
    
    try realm.write {
        
        /*
         Realm docs: If an object with a primary key 'id' already existed in the database, then that object would simply be updated. If it did not exist, then a completely new object would be created and added to the database.
         */
        if let text = record["text"] {
            
            // FIXME: Unsafe realm casting
            realm.create(objectClass as! Object.Type,
                value: ["id": id,
                    "text": text,
                    "dateModified": NSDate(),
                    "ckSystemFields": recordToLocalData(record)],
                update: true)
        }
    }
}
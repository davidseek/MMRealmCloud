import Foundation
import RealmSwift
import CloudKit
import PSOperations

public enum SyncType: CustomStringConvertible {
    case PushLocalChanges
    case FetchCloudChanges
    case PushLocalChangesAndThenFetchCloudChanges
    
    public var description : String {
        switch self {
        case .PushLocalChanges:
            return "Push Local Changes"
        case .FetchCloudChanges:
            return "Fetch Cloud Changes"
        case .PushLocalChangesAndThenFetchCloudChanges:
            return "Push Local Changes And Then Fetch Cloud Changes"
        }
    }
}

/**
 Sync local realm database with CloudKit.
 
 Required Conditions:
 - Reachability
 - iCloud
 
 Order of Operations:
 - PrepareZoneOperation
 - PushLocalChangesOperation
 - FetchCloudChangesOperation
 - completionHandler
 
 */
public class SyncOperation: GroupOperation {
    
    private var hasProducedAlert = false
    
    public init(zoneID: CKRecordZoneID,
         objectClass: RealmCloudObject.Type,
         syncType: SyncType,
         completionHandler: () -> Void) {
        
        let zoneChangeToken = getZoneChangeToken(zoneID)
        
        // Setup Conditions
        
        // ReachabilityCondition as written requires a URL so rather than rewriting, ping google
        let url = NSURL(string: "http://www.google.com")!
        let reachabilityCondition = ReachabilityCondition(host: url)
        
        let container = CKContainer.defaultContainer()
        let iCloudCapability = Capability(iCloudContainer(container: container))
        
        
        // Setup common operations
        let prepareZoneOperation = PrepareZoneOperation(zoneID: zoneID)
        let finishOperation = NSBlockOperation(block: completionHandler)
        
        prepareZoneOperation.addCondition(reachabilityCondition)
        prepareZoneOperation.addCondition(iCloudCapability)
        
        
        // Setup operations relating to SyncType
        let pushLocalChangesOperation: PushLocalChangesOperation
        let fetchCloudChangesOperation: FetchCloudChangesOperation
        let operations: [NSOperation]
        
        switch syncType {
        case .PushLocalChanges:
            pushLocalChangesOperation = PushLocalChangesOperation(zoneID: zoneID,
                                                                  objectClass: objectClass)
            
            pushLocalChangesOperation.addDependency(prepareZoneOperation)
            finishOperation.addDependency(pushLocalChangesOperation)
            
            operations = [
                prepareZoneOperation,
                pushLocalChangesOperation,
                finishOperation]
            
        case .FetchCloudChanges:
            fetchCloudChangesOperation = FetchCloudChangesOperation(zoneID: zoneID, objectClass: objectClass, previousServerChangeToken: zoneChangeToken)
            
            fetchCloudChangesOperation.addDependency(prepareZoneOperation)
            finishOperation.addDependency(fetchCloudChangesOperation)
            
            operations = [
                prepareZoneOperation,
                fetchCloudChangesOperation,
                finishOperation]
            
        case .PushLocalChangesAndThenFetchCloudChanges:
            pushLocalChangesOperation = PushLocalChangesOperation(zoneID: zoneID, objectClass: objectClass)
            fetchCloudChangesOperation = FetchCloudChangesOperation(zoneID: zoneID, objectClass: objectClass, previousServerChangeToken: zoneChangeToken)
            
            pushLocalChangesOperation.addDependency(prepareZoneOperation)
            fetchCloudChangesOperation.addDependency(pushLocalChangesOperation)
            finishOperation.addDependency(fetchCloudChangesOperation)
            
            operations = [
                prepareZoneOperation,
                pushLocalChangesOperation,
                fetchCloudChangesOperation,
                finishOperation]
        }
        
        super.init(operations: operations)
        
        
        name = "Sync \(syncType)"
    }
    
    override public func finished(errors: [NSError]) {
        if self.cancelled {
            print("Sync operation was cancelled.")
        }
    }
    
    override public func operationDidFinish(operation: NSOperation, withErrors errors: [NSError]) {
        if let firstError = errors.first {
            produceAlert(firstError)
        } else {
            if let name = operation.name {
                print("  \(name) finished")
            }
        }
    }
    
    private func produceAlert(error: NSError) {
        /*
         We only want to show the first error, since subsequent errors might
         be caused by the first.
         */
        if hasProducedAlert { return }
        
        produceOperation(createAlertOperation(error))
        
        hasProducedAlert = true
    }
}

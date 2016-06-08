import Foundation
import RealmSwift
import CloudKit

/**
 Declare a protocol to be implemented by Realm `Object`'s to be uploaded to CloudKit.
 */
public protocol RealmCloudObject {
    var id: String { get set }
    static func primaryKey() -> String?
    
    var isLocallyModified: Bool { get set }
    var isLocallyDeleted: Bool { get set }
    var ckSystemFields: NSData? { get set }
    
    func toRecord() -> CKRecord
}

extension RealmCloudObject {
    
    // TODO: implement toRecord() here using reflection on base class
    
    // TODO: implement saveSystemFields(record: CKRecord) here using refleciton on base class
    
    /**
     Unarchive the local CKRecord if one exists.
     */
    public func recordFromLocalData(archivedData: NSData?) -> CKRecord? {
        
        // Unarchive NSMutableData into CKRecord
        guard let data = archivedData where data.length > 0 else {
            print("warning: no data to unarchive")
            return nil
        }
        
        let unarchiver = NSKeyedUnarchiver(forReadingWithData: data)
        unarchiver.requiresSecureCoding = true
        let unarchivedRecord = CKRecord(coder: unarchiver)
        return unarchivedRecord
    }
}
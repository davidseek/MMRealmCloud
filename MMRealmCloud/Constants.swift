import Foundation
import CloudKit

// FIXME: questionable declaration of global zoneID
public let zoneID = CKRecordZoneID(zoneName: Constants.ZoneName, ownerName: CKOwnerDefaultName)

struct Constants {
    static let RecordType = "NoteType"
    static let ZoneName = "NoteZone"
}

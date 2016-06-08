# MMRealmCloud

## Motivation

The goal of this project is to determine and expose best practices for using Realm and CloudKit together. Realm is a fantastic local storage solution for iOS. CloudKit is an essentially free cloud storage solution.

## Limitations

- The project currently only supports storing data in the private database
  - By default transactions atomic in the private database meaning an error saving a single record from a batch will result in the entire batch failing.
- Ensure you push any local changes before fetching data because conflict resolution is handled in the `PushLocalChangesOperation`
- Currently any change to the record will result in the whole record being uploaded to the server. It would be more efficient to only send the modified keys to the server.

## Features

### Important
- [x] NSOperation subclassed Sync, Push and Fetch operations
- [x] Convenience functions for interfacing between Realm and CloudKit
- [ ] Add builtin reflection to  `RealmCloudObject` so custom properties don't need to be specified in convenience functions.
- [ ] Handle additional CloudKit error cases:
  - [ ] .ChangeTokenExpired
  - [ ] .UnknownItem
  - [ ] .UserDeletedZone (case where user deletes iCloud data)
- [ ] Unit tests (see Alamofire for good examples of how to do this)

### Future
- [ ] Add CloudKit Subscriptions (35 mins into WWDC 2015  CloudKit Tips and Tricks)
- [ ] Cleanup retry code in `PushLocalChangesOperation` and `FetchCloudChangesOperation`
- [ ] Add option to constrain viewing / editing of local data to a specific iCloud user
- [ ] Extend ideas to public database
- [ ] Extract into framework

## Usage

- Enable CloudKit in your project capabilities. Details on how to do this are available at [apple](https://developer.apple.com/library/ios/documentation/DataManagement/Conceptual/CloudKitQuickStart/EnablingiCloudandConfiguringCloudKit/EnablingiCloudandConfiguringCloudKit.html) and  [shinobicontrols](https://www.shinobicontrols.com/blog/ios8-day-by-day-day-33-cloudkit).

- Extend base Realm `Object` classes using `RealmCloudObject`
- Define class fields

```Swift
// Note.swift

class Note: Object, RealmCloudObject {

  // Define class fields.
  dynamic var text = ""
  dynamic var dateModified = NSDate()

  ...

}
```

- Modify the toRecord() function with the desired class fields. This function is used when sending records to CloudKit. (TODO: automate this using reflection)

```Swift
// Note.swift

func toRecord() -> CKRecord {
  ...
  record["text"] = self.text
  record["dateModified"] = self.dateModified
}
```

- Replace custom class name in saveSystemFields() function. (TODO: automate this using reflection)

```Swift
// Note.swift

func saveSystemFields(record: CKRecord) {
  ...
                realm.create(Note.self,
  ...
}
```

- Add desired class fields to changeLocalRecord() function. This function is used when receiving records from CloudKit. (TODO: automate this using reflection)

```Swift
// Note.swift
...

realm.create(objectClass as! Object.Type,
    value: ["id": id,
        "text": text,
        "dateModified": NSDate(),
        "ckSystemFields": recordToLocalData(record)],
    update: true)

...
```


- Set CKRecord type and CKRecordZone name.

```Swift
// Constants.swift

struct Constants {
    static let RecordType = "NoteType"
    static let ZoneName = "NoteZone"
}
```

## References

The project makes heavy use of ideas from the at [Advanced NSOperations 2015 WWDC session](https://developer.apple.com/videos/play/wwdc2015/226/). An adaptation of the WWDC code,  [PSOperations](https://github.com/pluralsight/PSOperations), is included as a dependency of this project.

### Related Projects

- [PSOperations](https://github.com/pluralsight/PSOperations)
- [EVCloudKitDao](https://github.com/evermeer/EVCloudKitDao): I learned a lot from this project.
- [Operations](https://github.com/danthorpe/Operations): A high level framework covering CloudKit among other things.


## License

MMRealmCloud is released under the MIT license. See LICENSE for details.

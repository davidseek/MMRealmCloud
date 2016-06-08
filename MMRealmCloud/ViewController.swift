import UIKit
import RealmSwift
import CloudKit
import PSOperations

class ViewController: UIViewController, UITableViewDelegate,
    UITableViewDataSource, NoteCellDelegate {
    
    @IBOutlet weak var tableView: UITableView!
    let operationQueue = OperationQueue()
    
    // MARK: - Realm
    var notificationToken: NotificationToken? = nil
    
    let noteResults: Results<Note> = {
        let realm = try! Realm()
        return realm.objects(Note)
            .filter("isLocallyDeleted == false")
            .sorted("dateModified", ascending: false)
    }()

    deinit {
        notificationToken?.stop()
    }
    
    // MARK: - Sync
    func sync(syncType: SyncType) {
        print("Beginning sync operation")
        
        let syncOperation = SyncOperation(zoneID: zoneID, objectClass: Note.self, syncType: syncType) {
            print("Sync complete!")
        }
        operationQueue.addOperation(syncOperation)
    }
    
    // MARK: - viewDidLoad
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("Open this path in Realm Browser (⌘ + Shift + G):\n"
            + Realm.Configuration.defaultConfiguration.fileURL!.path!)
        
        setupNavigationButtons()

        // Observe Results Notifications
        notificationToken = noteResults.addNotificationBlock { [weak self]
            (changes: RealmCollectionChange) in
            
            guard let tableView = self?.tableView else { return }
            switch changes {
            case .Initial:
                // Results are now populated and can be accessed without blocking the UI
                tableView.reloadData()
                break
            case .Update(_, let deletions, let insertions, let modifications):
                // Query results have changed, so apply them to the UITableView
                tableView.beginUpdates()
                tableView.insertRowsAtIndexPaths(
                    insertions.map { NSIndexPath(forRow: $0, inSection: 0) },
                    withRowAnimation: .Automatic)
                tableView.deleteRowsAtIndexPaths(
                    deletions.map { NSIndexPath(forRow: $0, inSection: 0) },
                    withRowAnimation: .Automatic)
                tableView.reloadRowsAtIndexPaths(
                    modifications.map { NSIndexPath(forRow: $0, inSection: 0) },
                    withRowAnimation: .Automatic)
                tableView.endUpdates()
                break
            case .Error(let error):
                // An error occurred while opening the Realm file on the background worker thread
                print(error)
                break
            }
        }
    }
    
    // MARK: - Actions
    func setupNavigationButtons() {
        
        let manualSyncButton = UIBarButtonItem(title: "Sync", style: .Plain, target: self, action: #selector(ViewController.manualSyncAction))
        let manualPushButton = UIBarButtonItem(title: "Push", style: .Plain, target: self, action: #selector(ViewController.manualPushAction))
        let manualFetchButton = UIBarButtonItem(title: "Fetch", style: .Plain, target: self, action: #selector(ViewController.manualFetchAction))
        let manualCancelButton = UIBarButtonItem(title: "Cancel", style: .Plain, target: self, action: #selector(ViewController.cancelOperationsAction))
        let newItemButton = UIBarButtonItem(barButtonSystemItem: .Add, target: self, action: #selector(ViewController.addItemAction))
        
        navigationItem.rightBarButtonItems = [newItemButton, manualCancelButton, manualPushButton, manualFetchButton, manualSyncButton]
    }
    
    func addItemAction() {
        addNote()
    }
    
    func manualSyncAction() {
        sync(.PushLocalChangesAndThenFetchCloudChanges)
    }
    
    func manualPushAction() {
        sync(.PushLocalChanges)
    }
    
    func manualFetchAction() {
        sync(.FetchCloudChanges)
    }
    
    func cancelOperationsAction() {
        operationQueue.cancelAllOperations()
    }
    
    // MARK: - TableViewDatasource
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return noteResults.count
    }
    
    func tableView(tableView: UITableView,
                   cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCellWithIdentifier("NoteCell", forIndexPath: indexPath) as! NoteCell
        
        let note = noteForIndexPath(indexPath)
        cell.configureWith(note)
        
        if cell.delegate == nil {
            cell.delegate = self
        }
        
        return cell
    }
    
    
    // MARK: - TableViewDelegate
    func tableView(tableView: UITableView, editActionsForRowAtIndexPath indexPath: NSIndexPath) -> [UITableViewRowAction]? {
        
        let note = noteForIndexPath(indexPath)
        let delete = UITableViewRowAction(style: .Destructive, title: "Delete") {
            (action, indexPath) in
            print("Deleting note locally: \(note.id)")
            self.deleteNote(self.noteForIndexPath(indexPath), indexPath: indexPath)
        }
        return [delete]

    }
    
    func tableView(tableView: UITableView, willDisplayCell cell: UITableViewCell, forRowAtIndexPath indexPath: NSIndexPath) {
        cell.selectionStyle = .None
    }
    
    // MARK: - Data
    func addNote() {
        do {
//            throw RealmSwift.Error.Fail
            let realm = try Realm()
            try realm.write {
                let note = Note()
                note.text = "Note \(String(format: "%04X", arc4random_uniform(UInt32(UInt16.max))))"
                note.isLocallyModified = true
                print("add: \(note.id)")
                realm.add(note)
            }
        } catch let realmError as NSError {
            produceAlert(realmError)
        }
    }
    
    func deleteNote(note: Note, indexPath: NSIndexPath) {
        do {
            try setDeleted(note.id, type: Note.self, value: true)
        } catch let realmError as NSError {
            produceAlert(realmError)
        }
    }
    
    // MARK: NoteCellDelegate
    func textEdited(cell: UITableViewCell, text: String) {
        if let indexPath = tableView.indexPathForCell(cell) {
            
            let realm = try! Realm()
            try! realm.write {
                let note = noteForIndexPath(indexPath)
                note.text = text
                note.dateModified = NSDate()
                note.isLocallyModified = true
                
            }
        }
    }
    
    // MARK: - Helpers
    func noteForIndexPath(indexPath: NSIndexPath) -> Note {
        return noteResults[indexPath.row]
    }
    
    func produceAlert(error: NSError) {
        operationQueue.addOperation(createAlertOperation(error))
    }
}

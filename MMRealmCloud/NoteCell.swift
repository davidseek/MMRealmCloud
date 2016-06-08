import UIKit

protocol NoteCellDelegate {
    func textEdited(cell: UITableViewCell, text: String)
}

class NoteCell: UITableViewCell, UITextFieldDelegate {
    
    var delegate: NoteCellDelegate?
    
    @IBOutlet weak var noteField: UITextField!
    
    func configureWith(note: Note) {
        noteField.text = note.text
        noteField.delegate = self
    }
    
    // MARK: - UITextFieldDelegate methods
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
    
    func textFieldDidEndEditing(textField: UITextField) {
        if let delegate = delegate {
            delegate.textEdited(self, text: textField.text!)
        }
    }
}

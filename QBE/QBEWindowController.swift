import Foundation

import Cocoa

class QBEWindowController: NSWindowController {
    override var document: AnyObject? {
        didSet {
            let qbeDocumentViewController = window!.contentViewController as QBEViewController
            qbeDocumentViewController.document = document as? QBEDocument
        }
    }
    
    /*override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == SegueIdentifiers.showAddItemViewController {
            let listViewController = window!.contentViewController as ListViewController
            
            let addItemViewController = segue.destinationController as AddItemViewController
            
            addItemViewController.delegate = listViewController
        }
    }*/
    
    // MARK: IBActions
    
    @IBAction func shareDocument(sender: NSObject) {
        /*if let listDocument = document as? ListDocument {
            let listContents = ListFormatting.stringFromListItems(listDocument.list.items)
            
            let sharingServicePicker = NSSharingServicePicker(items: [listContents])
            
            let preferredEdge =  NSRectEdge(CGRectEdge.MinYEdge.rawValue)
            sharingServicePicker.showRelativeToRect(NSZeroRect, ofView: sender, preferredEdge: preferredEdge)
        }*/
    }
}

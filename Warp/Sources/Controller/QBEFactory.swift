import Foundation
import WarpCore

protocol QBEStepViewDelegate: NSObjectProtocol {
	var locale: Locale { get }

	func stepView(view: QBEStepViewController, didChangeConfigurationForStep: QBEStep)
}

class QBEStepViewController: NSViewController {
	required init?(step: QBEStep, delegate: QBEStepViewDelegate) {
		fatalError("Do not call")
	}

	override init?(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
}

class QBEStepViewControllerFor<StepType: QBEStep>: QBEStepViewController {
	weak var delegate: QBEStepViewDelegate?
	var step: StepType

	init?(step: QBEStep, delegate: QBEStepViewDelegate, nibName: String?, bundle: NSBundle?) {
		self.step = step as! StepType
		self.delegate = delegate
		super.init(nibName: nibName, bundle: bundle)
	}

	required init?(step: QBEStep, delegate: QBEStepViewDelegate) {
		fatalError("init(coder:) has not been implemented")
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
}

class QBEFactory {
	typealias QBEStepViewCreator = (step: QBEStep?, delegate: QBESuggestionsViewDelegate) -> NSViewController?
	typealias QBEFileReaderCreator = (url: NSURL) -> QBEStep?
	
	static let sharedInstance = QBEFactory()
	
	let fileWriters: [QBEFileWriter.Type] = [
		QBECSVWriter.self,
		QBEXMLWriter.self,
		QBEHTMLWriter.self,
		QBEDBFWriter.self,
		QBESQLiteWriter.self
	]

	let dataWarehouseSteps: [QBEStep.Type] = [
		QBEMySQLSourceStep.self,
		QBEPostgresSourceStep.self,
		QBERethinkSourceStep.self,
		QBESQLiteSourceStep.self
	]

	let dataWarehouseStepNames: [String: String] = [
		QBEMySQLSourceStep.className(): NSLocalizedString("MySQL table", comment: ""),
		QBEPostgresSourceStep.className(): NSLocalizedString("PostgreSQL table", comment: ""),
		QBERethinkSourceStep.className(): NSLocalizedString("RethinkDB table", comment: ""),
		QBESQLiteSourceStep.className(): NSLocalizedString("SQLite table", comment: "")
	]
	
	private let fileReaders: [String: QBEFileReaderCreator] = [
		"public.comma-separated-values-text": {(url) in return QBECSVSourceStep(url: url)},
		"csv": {(url) in return QBECSVSourceStep(url: url)},
		"tsv": {(url) in return QBECSVSourceStep(url: url)},
		"txt": {(url) in return QBECSVSourceStep(url: url)},
		"tab": {(url) in return QBECSVSourceStep(url: url)},
		"public.delimited-values-text": {(url) in return QBECSVSourceStep(url: url)},
		"public.tab-separated-values-text": {(url) in return QBECSVSourceStep(url: url)},
		"public.text": {(url) in return QBECSVSourceStep(url: url)},
		"public.plain-text": {(url) in return QBECSVSourceStep(url: url)},
		"org.sqlite.v3": {(url) in return QBESQLiteSourceStep(url: url)},
		"sqlite": {(url) in return QBESQLiteSourceStep(url: url)},
		"dbf": {(url) in return QBEDBFSourceStep(url: url)}
	]
	
	private let stepViews: Dictionary<String, QBEStepViewController.Type> = [
		QBECalculateStep.className(): QBECalculateStepView.self,
		QBEPivotStep.className(): QBEPivotStepView.self,
		QBECSVSourceStep.className(): QBECSVStepView.self,
		QBEPrestoSourceStep.className(): QBEPrestoSourceStepView.self,
		QBEColumnsStep.className(): QBEColumnsStepView.self,
		QBESortStep.className(): QBESortStepView.self,
		QBEMySQLSourceStep.className(): QBEMySQLSourceStepView.self,
		QBERenameStep.className(): QBERenameStepView.self,
		QBEPostgresSourceStep.className(): QBEPostgresStepView.self,
		QBECrawlStep.className(): QBECrawlStepView.self,
		QBERethinkSourceStep.className(): QBERethinkStepView.self,
		QBEJoinStep.className(): QBEJoinStepView.self,
		QBESQLiteSourceStep.className(): QBESQLiteSourceStepView.self
	]
	
	private let stepIcons = [
		QBETransposeStep.className(): "TransposeIcon",
		QBEPivotStep.className(): "PivotIcon",
		QBERandomStep.className(): "RandomIcon",
		QBEFilterStep.className(): "FilterIcon",
		QBELimitStep.className(): "LimitIcon",
		QBEOffsetStep.className(): "LimitIcon",
		QBECSVSourceStep.className(): "CSVIcon",
		QBESQLiteSourceStep.className(): "SQLIcon",
		QBECalculateStep.className(): "CalculateIcon",
		QBEColumnsStep.className(): "ColumnsIcon",
		QBESortColumnsStep.className(): "ColumnsIcon",
		QBEFlattenStep.className(): "FlattenIcon",
		QBEDistinctStep.className(): "DistinctIcon",
		QBEPrestoSourceStep.className(): "PrestoIcon",
		QBERasterStep.className(): "RasterIcon",
		QBESortStep.className(): "SortIcon",
		QBEMySQLSourceStep.className(): "MySQLIcon",
		QBEPostgresSourceStep.className(): "PostgresIcon",
		QBEJoinStep.className(): "JoinIcon",
		QBECloneStep.className(): "CloneIcon",
		QBEDebugStep.className(): "DebugIcon",
		QBERenameStep.className(): "RenameIcon",
		QBEMergeStep.className(): "MergeIcon",
		QBECrawlStep.className(): "CrawlIcon",
		QBESequencerStep.className(): "SequenceIcon",
		QBEDBFSourceStep.className(): "DBFIcon",
		QBEExportStep.className(): "ExportStepIcon",
		QBERethinkSourceStep.className(): "RethinkDBIcon"
	]
	
	var fileExtensionsForWriting: Set<String> { get {
		var exts = Set<String>()
		for writer in fileWriters {
			exts.unionInPlace(writer.fileTypes)
		}
		return exts
	} }
	
	var fileTypesForReading: [String] { get {
		return [String](fileReaders.keys)
	} }
	
	func stepForReadingFile(atURL: NSURL) -> QBEStep? {
		do {
			let type = try NSWorkspace.sharedWorkspace().typeOfFile(atURL.path!)
			if let creator = fileReaders[type] {
				return creator(url: atURL)
			}

			if let p = atURL.path {
				let ext = NSString(string: p).pathExtension
				if let creator = fileReaders[ext] {
					return creator(url: atURL)
				}
			}
		}
		catch { }
		return nil
	}
	
	func fileWriterForType(type: String) -> QBEFileWriter.Type? {
		for writer in fileWriters {
			if writer.fileTypes.contains(type) {
				return writer
			}
		}
		return nil
	}

	func hasViewForStep(step: QBEStep) -> Bool {
		return stepViews[step.self.className] != nil
	}

	func viewForStep<StepType: QBEStep>(step: StepType, delegate: QBEStepViewDelegate) -> QBEStepViewController? {
		if let viewType = stepViews[step.className] {
			return viewType.init(step: step, delegate: delegate)
		}
		return nil
	}
	
	func iconForStep(step: QBEStep) -> String? {
		return stepIcons[step.className]
	}
	
	func iconForStepType(type: QBEStep.Type) -> String? {
		return stepIcons[type.className()]
	}
}
/* Warp. Copyright (C) 2014-2016 Pixelspark, Tommy van der Vorst

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public
License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied
warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free
Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA. */
import Foundation
import WarpCore

public protocol QBEConfigurable: NSObjectProtocol {
	func sentence(_ locale: Language, variant: QBESentenceVariant) -> QBESentence
	var className: String { get }
}

public protocol QBEFullyConfigurable: QBEConfigurable {
	func setSentence(_ sentence: QBESentence)
}

protocol QBEConfigurableViewDelegate: NSObjectProtocol {
	var locale: Language { get }

	func configurableView(_ view: QBEConfigurableViewController, didChangeConfigurationFor: QBEConfigurable)
}

class QBEConfigurableViewController: NSViewController {
	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		fatalError("Do not call")
	}

	override init?(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
}

class QBEConfigurableStepViewControllerFor<StepType: QBEStep>: QBEConfigurableViewController {
	weak var delegate: QBEConfigurableViewDelegate?
	var step: StepType

	init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate, nibName: String?, bundle: Bundle?) {
		self.step = configurable as! StepType
		self.delegate = delegate
		super.init(nibName: nibName, bundle: bundle)
	}

	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		fatalError("init(coder:) has not been implemented")
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
}

class QBEFactory {
	typealias QBEStepViewCreator = (_ step: QBEStep?, _ delegate: QBESuggestionsViewDelegate) -> NSViewController?
	typealias QBEFileReaderCreator = (_ url: URL) -> QBEStep?

	static var sharedInstance = QBEFactory()
	
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
	
	private let configurableViews: Dictionary<String, QBEConfigurableViewController.Type> = [
		QBECalculateStep.className(): QBECalculateStepView.self,
		QBEPivotStep.className(): QBEPivotStepView.self,
		QBECSVSourceStep.className(): QBECSVStepView.self,
		QBESortStep.className(): QBESortStepView.self,
		QBEMySQLSourceStep.className(): QBEMySQLSourceStepView.self,
		QBERenameStep.className(): QBERenameStepView.self,
		QBEPostgresSourceStep.className(): QBEPostgresStepView.self,
		QBECrawlStep.className(): QBECrawlStepView.self,
		QBERethinkSourceStep.className(): QBERethinkStepView.self,
		QBEJoinStep.className(): QBEJoinStepView.self,
		QBESQLiteSourceStep.className(): QBESQLiteSourceStepView.self,
		QBECacheStep.className(): QBECacheStepView.self
	]
	
	private let stepIcons = [
		QBETransposeStep.className(): "TransposeIcon",
		QBEPivotStep.className(): "PivotIcon",
		QBERandomStep.className(): "RandomIcon",
		QBEFilterStep.className(): "FilterIcon",
		QBEFilterSetStep.className(): "FilterIcon",
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
		QBERethinkSourceStep.className(): "RethinkDBIcon",
		QBEClassifierStep.className(): "AIIcon",
		QBEExplodeVerticallyStep.className(): "ExplodeVerticalIcon",
		QBEExplodeHorizontallyStep.className(): "ExplodeHorizontalIcon",
		QBECacheStep.className(): "CacheIcon",
		QBEDummiesStep.className(): "DummiesIcon",
		QBEHTTPStep.className(): "DownloadIcon",
		QBEFileStep.className(): "TextIcon",
		QBESearchStep.className(): "SearchIcon"
	]
	
	var fileExtensionsForWriting: Set<String> { get {
		var exts = Set<String>()
		for writer in fileWriters {
			exts.formUnion(writer.fileTypes)
		}
		return exts
	} }
	
	var fileTypesForReading: [String] { get {
		return [String](fileReaders.keys)
	} }
	
	func stepForReadingFile(_ atURL: URL) -> QBEStep? {
		do {
			// Try to find reader by UTI type
			let type = try NSWorkspace.shared().type(ofFile: atURL.path)
			for (readerType, creator) in fileReaders {
				if NSWorkspace.shared().type(type, conformsToType: readerType) {
					return creator(atURL)
				}
			}

			// Try by file extension
			let ext = atURL.pathExtension
			if ext == "warp" {
				return nil
			}
			else if let creator = fileReaders[ext] {
				return creator(atURL)
			}

			// Generic file reader
			return QBEFileStep(file: QBEFileReference.absolute(atURL))
		}
		catch { }
		return nil
	}
	
	func fileWriterForType(_ type: String) -> QBEFileWriter.Type? {
		for writer in fileWriters {
			if writer.fileTypes.contains(type) {
				return writer
			}
		}
		return nil
	}

	func hasViewForConfigurable(_ configurable: QBEConfigurable) -> Bool {
		return configurableViews[configurable.className] != nil
	}

	func viewForConfigurable(_ step: QBEConfigurable, delegate: QBEConfigurableViewDelegate) -> QBEConfigurableViewController? {
		if let viewType = configurableViews[step.className] {
			return viewType.init(configurable: step, delegate: delegate)
		}
		return nil
	}
	
	func iconForStep(_ step: QBEStep) -> String? {
		return stepIcons[step.className]
	}
	
	func iconForStepType(_ type: QBEStep.Type) -> String? {
		return stepIcons[type.className()]
	}

	func viewControllerForTablet(_ tablet: QBETablet, storyboard: NSStoryboard) -> QBETabletViewController {
		let tabletController: QBETabletViewController
		if tablet is QBEChainTablet {
			tabletController = storyboard.instantiateController(withIdentifier: "chainTablet") as! QBEChainTabletViewController
		}
		else if tablet is QBENoteTablet {
			tabletController = storyboard.instantiateController(withIdentifier: "noteTablet") as! QBENoteTabletViewController
		}
		else if tablet is QBEChartTablet {
			tabletController = storyboard.instantiateController(withIdentifier: "chartTablet") as! QBEChartTabletViewController
		}
		else if tablet is QBEMapTablet {
			tabletController = storyboard.instantiateController(withIdentifier: "mapTablet") as! QBEMapTabletViewController
		}
		else {
			fatalError("No view controller found for tablet type")
		}

		tabletController.tablet = tablet
		tabletController.view.frame = tablet.frame!
		return tabletController
	}

}

/* Warp. Copyright (C) 2014-2017 Pixelspark, Tommy van der Vorst

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
}

public protocol QBEFullyConfigurable: QBEConfigurable {
	var isEditable: Bool { get }
	func setSentence(_ sentence: QBESentence)
}

#if os(macOS)

import Cocoa

protocol QBEConfigurableViewDelegate: NSObjectProtocol {
	var locale: Language { get }

	func configurableView(_ view: QBEConfigurableViewController, didChangeConfigurationFor: QBEConfigurable)
}

class QBEConfigurableViewController: NSViewController {
	required init?(configurable: QBEConfigurable, delegate: QBEConfigurableViewDelegate) {
		fatalError("Do not call")
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
		super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
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
#endif

class QBEFactory {
	#if os(macOS)
	typealias QBEStepViewCreator = (_ step: QBEStep?, _ delegate: QBESuggestionsViewDelegate) -> NSViewController?
	#endif
	
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
		QBESQLiteSourceStep.self
	]

	let dataWarehouseStepNames: [String: String] = [
		NSStringFromClass(QBEMySQLSourceStep.self): NSLocalizedString("MySQL table", comment: ""),
		NSStringFromClass(QBEPostgresSourceStep.self): NSLocalizedString("PostgreSQL table", comment: ""),
		NSStringFromClass(QBESQLiteSourceStep.self): NSLocalizedString("SQLite table", comment: "")
	]

	private let fileReaders: [String: QBEFileReaderCreator] = [
		"json": {(url) in return QBEJSONSourceStep(url: url)},
		"public.json": {(url) in return QBEJSONSourceStep(url: url)},
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
		"nl.pixelspark.warp.sqlite": {(url) in return QBESQLiteSourceStep(url: url)},
		"nl.pixelspark.warp.dbf": {(url) in return QBEDBFSourceStep(url: url)},
		"nl.pixelspark.warp.csv": {(url) in return QBECSVSourceStep(url: url)},
		"sqlite": {(url) in return QBESQLiteSourceStep(url: url)},
		"dbf": {(url) in return QBEDBFSourceStep(url: url)},
	]

	public var supportedFileTypes: [String] {
		return Array(self.fileReaders.keys)
	}

	#if os(macOS)
	private let configurableViews: Dictionary<String, QBEConfigurableViewController.Type> = [
		QBECalculateStep.className(): QBECalculateStepView.self,
		QBEPivotStep.className(): QBEPivotStepView.self,
		QBECSVSourceStep.className(): QBECSVStepView.self,
		QBESortStep.className(): QBESortStepView.self,
		QBEMySQLSourceStep.className(): QBEMySQLSourceStepView.self,
		QBERenameStep.className(): QBERenameStepView.self,
		QBEPostgresSourceStep.className(): QBEPostgresStepView.self,
		QBECrawlStep.className(): QBECrawlStepView.self,
		QBEJoinStep.className(): QBEJoinStepView.self,
		QBESQLiteSourceStep.className(): QBESQLiteSourceStepView.self,
		QBECacheStep.className(): QBECacheStepView.self,
	]
	#endif

	private let stepIcons: [String:String] = [
		NSStringFromClass(QBECloneStep.self): "CloneIcon",
		NSStringFromClass(QBESequencerStep.self): "SequenceIcon",
		NSStringFromClass(QBELimitStep.self): "LimitIcon",
		NSStringFromClass(QBEOffsetStep.self): "LimitIcon",
		NSStringFromClass(QBERandomStep.self): "RandomIcon",
		NSStringFromClass(QBEPostgresSourceStep.self): "PostgresIcon",
		NSStringFromClass(QBESearchStep.self): "SearchIcon",
		NSStringFromClass(QBETransposeStep.self): "TransposeIcon",
		NSStringFromClass(QBEDistinctStep.self): "DistinctIcon",
		NSStringFromClass(QBECSVSourceStep.self): "CSVIcon",
		NSStringFromClass(QBESQLiteSourceStep.self): "SQLIcon",
		NSStringFromClass(QBEMySQLSourceStep.self): "MySQLIcon",
		NSStringFromClass(QBEDBFSourceStep.self): "DBFIcon",
		NSStringFromClass(QBEFlattenStep.self): "FlattenIcon",
		NSStringFromClass(QBEPivotStep.self): "PivotIcon",
		NSStringFromClass(QBEFilterStep.self): "FilterIcon",
		NSStringFromClass(QBEFilterSetStep.self): "FilterIcon",
		NSStringFromClass(QBECalculateStep.self): "CalculateIcon",
		NSStringFromClass(QBEColumnsStep.self): "ColumnsIcon",
		NSStringFromClass(QBESortColumnsStep.self): "ColumnsIcon",
		NSStringFromClass(QBERasterStep.self): "RasterIcon",
		NSStringFromClass(QBESortStep.self): "SortIcon",
		NSStringFromClass(QBEJoinStep.self): "JoinIcon",
		NSStringFromClass(QBEDebugStep.self): "DebugIcon",
		NSStringFromClass(QBERenameStep.self): "RenameIcon",
		NSStringFromClass(QBEMergeStep.self): "MergeIcon",
		NSStringFromClass(QBECrawlStep.self): "CrawlIcon",
		NSStringFromClass(QBEExportStep.self): "ExportStepIcon",
		NSStringFromClass(QBEExplodeVerticallyStep.self): "ExplodeVerticalIcon",
		NSStringFromClass(QBEExplodeHorizontallyStep.self): "ExplodeHorizontalIcon",
		NSStringFromClass(QBECacheStep.self): "CacheIcon",
		NSStringFromClass(QBEDummiesStep.self): "DummiesIcon",
		NSStringFromClass(QBEHTTPStep.self): "DownloadIcon",
		NSStringFromClass(QBEFileStep.self): "TextIcon",
		NSStringFromClass(QBEJSONSourceStep.self): "JSONIcon",
		NSStringFromClass(QBERankStep.self): "RankIcon",
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
			#if os(macOS)
				// Try to find reader by UTI type
				let type = try NSWorkspace.shared.type(ofFile: atURL.path)

				// Exact match
				if let creator = fileReaders[type] {
					return creator(atURL)
				}

				// Conformance match
				for (readerType, creator) in fileReaders {
					if NSWorkspace.shared.type(type, conformsToType: readerType) {
						return creator(atURL)
					}
				}
			#endif

			// Try by file extension
			let ext = atURL.pathExtension
			if ext == "warp" {
				return nil
			}
			else if let creator = fileReaders[ext] {
				return creator(atURL)
			}

			// Generic file reader
			#if os(macOS)
			return QBEFileStep(file: QBEFileReference.absolute(atURL))
			#endif
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

	#if os(macOS)
	func hasViewForConfigurable(_ configurable: QBEConfigurable) -> Bool {
		return configurableViews[NSStringFromClass(type(of: configurable))] != nil
	}

	func viewForConfigurable(_ step: QBEConfigurable, delegate: QBEConfigurableViewDelegate) -> QBEConfigurableViewController? {
		if let viewType = configurableViews[NSStringFromClass(type(of: step))] {
			return viewType.init(configurable: step, delegate: delegate)
		}
		return nil
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
	#endif

	func iconForStep(_ step: QBEStep) -> String? {
		return stepIcons[NSStringFromClass(type(of: step))]
	}
	
	func iconForStepType(_ type: QBEStep.Type) -> String? {
		return stepIcons[NSStringFromClass(type)]
	}
}

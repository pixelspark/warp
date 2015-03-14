import Foundation
import Cocoa

typealias QBEStepView = (step: QBEStep?, delegate: QBESuggestionsViewDelegate) -> NSViewController?

let QBEStepViews: Dictionary<String, QBEStepView> = [
	QBESQLiteSourceStep.className(): {QBESQLiteSourceStepView(step: $0, delegate: $1)},
	QBELimitStep.className(): {QBELimitStepView(step: $0, delegate: $1)},
	QBEOffsetStep.className(): {QBEOffsetStepView(step: $0, delegate: $1)},
	QBERandomStep.className(): {QBERandomStepView(step: $0, delegate: $1)},
	QBECalculateStep.className(): {QBECalculateStepView(step: $0, delegate: $1)},
	QBEPivotStep.className(): {QBEPivotStepView(step: $0, delegate: $1)},
	QBECSVSourceStep.className(): {QBECSVStepView(step: $0, delegate: $1)},
	QBEFilterStep.className(): {QBEFilterStepView(step: $0, delegate: $1)},
	QBEFlattenStep.className(): {QBEFlattenStepView(step: $0, delegate: $1)},
	QBEPrestoSourceStep.className(): {QBEPrestoSourceStepView(step: $0, delegate: $1)},
	QBEColumnsStep.className(): {QBEColumnsStepView(step: $0, delegate: $1)},
]

let QBEStepIcons = [
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
	QBEFlattenStep.className(): "FlattenIcon",
	QBEDistinctStep.className(): "DistinctIcon",
	QBEPrestoSourceStep.className(): "PrestoIcon"
]
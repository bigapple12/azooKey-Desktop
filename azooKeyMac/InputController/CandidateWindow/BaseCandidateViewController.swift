import Cocoa
import Core
import KanaKanjiConverterModule

class NonClickableTableView: NSTableView {
    override func rightMouseDown(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}

class CandidateTableCellView: NSTableCellView {
    let candidateTextField: NSTextField
    let sparkleImageView: NSImageView

    override init(frame frameRect: NSRect) {
        self.candidateTextField = NSTextField(labelWithString: "")
        self.candidateTextField.font = NSFont.systemFont(ofSize: 18)

        self.sparkleImageView = NSImageView()
        if let sparkleImage = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI") {
            self.sparkleImageView.image = sparkleImage
        }
        self.sparkleImageView.isHidden = true
        self.sparkleImageView.contentTintColor = .systemPurple

        super.init(frame: frameRect)
        self.addSubview(self.sparkleImageView)
        self.addSubview(self.candidateTextField)

        self.sparkleImageView.translatesAutoresizingMaskIntoConstraints = false
        self.candidateTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.sparkleImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 2),
            self.sparkleImageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.sparkleImageView.widthAnchor.constraint(equalToConstant: 16),
            self.sparkleImageView.heightAnchor.constraint(equalToConstant: 16),

            self.candidateTextField.leadingAnchor.constraint(equalTo: self.sparkleImageView.trailingAnchor, constant: 2),
            self.candidateTextField.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.candidateTextField.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])

        // 基本設定
        self.candidateTextField.isEditable = false
        self.candidateTextField.isBordered = false
        self.candidateTextField.drawsBackground = false
        self.candidateTextField.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            candidateTextField.textColor = backgroundStyle == .emphasized ? .white : NSAppearance.currentDrawing().name == .aqua ? .init(white: 0.3, alpha: 1.0) : .textColor
            sparkleImageView.contentTintColor = backgroundStyle == .emphasized ? .white : .systemPurple
        }
    }
}

class BaseCandidateViewController: NSViewController {
    internal var candidates: [Candidate] = []
    internal var aiCandidateIndices: Set<Int> = []
    internal var tableView: NSTableView!
    internal var currentSelectedRow: Int = -1

    // ステータスヘッダー（AIモード表示）
    internal var statusHeaderView: NSView!
    internal var modeLabel: NSTextField!
    internal var loadingSpinner: NSProgressIndicator!
    internal var statusHeaderHeightConstraint: NSLayoutConstraint!
    private static let headerHeight: CGFloat = 20

    override func loadView() {
        // 親ビュー（ZStackのような役割）
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Material View（背景）
        let materialView = NSVisualEffectView()
        materialView.blendingMode = .behindWindow
        materialView.material = .windowBackground
        materialView.state = .active
        materialView.translatesAutoresizingMaskIntoConstraints = false

        // ステータスヘッダー（AIモード名 + ローディング）
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.backgroundColor = .clear
        label.lineBreakMode = .byTruncatingTail
        self.modeLabel = label

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        self.loadingSpinner = spinner

        headerView.addSubview(label)
        headerView.addSubview(spinner)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -4),

            spinner.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -6),
            spinner.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 12),
            spinner.heightAnchor.constraint(equalToConstant: 12)
        ])

        self.statusHeaderView = headerView

        // Scroll View（前面）
        let scrollView = NSScrollView()
        self.tableView = NonClickableTableView()
        self.tableView.style = .plain
        scrollView.documentView = self.tableView
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // 重ね順に応じて subviews を構成（背面 → 前面）
        containerView.subviews = [materialView, headerView, scrollView]

        // ヘッダー高さ制約（非表示時は0）
        let headerHeightConstraint = headerView.heightAnchor.constraint(equalToConstant: 0)
        self.statusHeaderHeightConstraint = headerHeightConstraint

        // 制約
        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: containerView.topAnchor),
            materialView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            headerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerHeightConstraint,

            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.tableView.backgroundColor = .clear
        self.tableView.gridStyleMask = .solidHorizontalGridLineMask

        // テーブルビューの構成
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CandidatesColumn"))
        self.tableView.headerView = nil
        self.tableView.addTableColumn(column)
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.selectionHighlightStyle = .regular
        self.tableView.rowHeight = 28

        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureWindowForRoundedCorners()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureWindowForRoundedCorners()
    }

    internal func configureWindowForRoundedCorners() {
        guard let window = self.view.window else {
            return
        }

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.masksToBounds = true

        window.styleMask = [.borderless, .resizable]
        window.isMovable = true
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        window.contentView?.layer?.cornerRadius = 10
        window.backgroundColor = .clear
        window.isOpaque = false
    }

    func updateCandidates(
        _ candidates: [Candidate],
        selectionIndex: Int?,
        cursorLocation: CGPoint,
        aiCandidateIndices: Set<Int> = [],
        aiPresetName: String? = nil,
        isAIProcessing: Bool = false
    ) {
        self.candidates = candidates
        self.aiCandidateIndices = aiCandidateIndices
        self.updateStatusHeader(aiPresetName: aiPresetName, isAIProcessing: isAIProcessing)
        self.currentSelectedRow = selectionIndex ?? -1
        self.tableView.reloadData()
        self.resizeWindowToFitContent(cursorLocation: cursorLocation)
        self.updateSelection(to: selectionIndex ?? -1)
    }

    /// ステータスヘッダーの表示を更新
    /// aiPresetName が "AI:" で始まらない場合（組み込みモード）はプレフィックスなしで表示
    internal func updateStatusHeader(aiPresetName: String?, isAIProcessing: Bool) {
        if let name = aiPresetName {
            self.statusHeaderHeightConstraint.constant = Self.headerHeight
            self.statusHeaderView.isHidden = false
            // 組み込みモード（カタカナ/alphabet）はそのまま、AIプリセットは "AI: " プレフィックス付き
            let isBuiltIn = (name == "カタカナ" || name == "alphabet")
            self.modeLabel.stringValue = isBuiltIn ? name : "AI: \(name)"
            if isAIProcessing {
                self.loadingSpinner.isHidden = false
                self.loadingSpinner.startAnimation(nil)
            } else {
                self.loadingSpinner.stopAnimation(nil)
                self.loadingSpinner.isHidden = true
            }
        } else {
            self.statusHeaderHeightConstraint.constant = 0
            self.statusHeaderView.isHidden = true
            self.loadingSpinner.stopAnimation(nil)
            self.loadingSpinner.isHidden = true
        }
    }

    internal func updateSelection(to row: Int) {
        if row == -1 {
            return
        }
        self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        self.tableView.scrollRowToVisible(row)
        self.updateSelectionCallback(row)
        self.currentSelectedRow = row
        self.updateVisibleRows()
    }

    internal func updateSelectionCallback(_ row: Int) {}

    internal func updateVisibleRows() {
        let visibleRows = self.tableView.rows(in: self.tableView.visibleRect)
        for row in visibleRows.lowerBound..<visibleRows.upperBound {
            if let cellView = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? CandidateTableCellView {
                self.configureCellView(cellView, forRow: row)
            }
        }
    }

    func getMaxTextWidth(candidates: some Sequence<String>, font: NSFont = .systemFont(ofSize: 18)) -> CGFloat {
        candidates.reduce(0) { maxWidth, candidate in
            let attributedString = NSAttributedString(
                string: candidate,
                attributes: [.font: font]
            )
            return max(maxWidth, attributedString.size().width)
        }
    }

    var numberOfVisibleRows: Int {
        self.candidates.count
    }

    func getWindowWidth(maxContentWidth: CGFloat) -> CGFloat {
        maxContentWidth
    }

    func resizeWindowToFitContent(cursorLocation: CGPoint) {
        guard let window = self.view.window, let screen = window.screen else {
            return
        }

        if self.numberOfVisibleRows == 0 {
            return
        }

        let rowHeight = self.tableView.rowHeight
        let headerHeight = self.statusHeaderHeightConstraint.constant
        let tableViewHeight = CGFloat(self.numberOfVisibleRows) * rowHeight + headerHeight

        let maxWidth = self.getMaxTextWidth(candidates: self.candidates.lazy.map { $0.text })
        let windowWidth = self.getWindowWidth(maxContentWidth: maxWidth)
        let newWindowFrame = WindowPositioning.frameNearCursor(
            currentFrame: .init(window.frame),
            screenRect: .init(screen.visibleFrame),
            cursorLocation: .init(cursorLocation),
            desiredSize: .init(width: windowWidth, height: tableViewHeight)
        ).cgRect
        if newWindowFrame != window.frame {
            window.setFrame(newWindowFrame, display: true, animate: false)
        }
    }

    func getSelectedCandidate() -> Candidate? {
        guard currentSelectedRow >= 0 && currentSelectedRow < candidates.count else {
            return nil
        }
        return candidates[currentSelectedRow]
    }

    func selectNextCandidate() {
        guard !candidates.isEmpty else {
            return
        }
        let nextRow = (currentSelectedRow + 1) % candidates.count
        updateSelection(to: nextRow)
    }

    func selectPrevCandidate() {
        guard !candidates.isEmpty else {
            return
        }
        let prevRow = (currentSelectedRow - 1 + candidates.count) % candidates.count
        updateSelection(to: prevRow)
    }

    internal func configureCellView(_ cell: CandidateTableCellView, forRow row: Int) {
        cell.candidateTextField.stringValue = candidates[row].text
        cell.sparkleImageView.isHidden = !aiCandidateIndices.contains(row)
    }
}

extension BaseCandidateViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        candidates.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("CandidateCell")
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? CandidateTableCellView

        if cell == nil {
            cell = CandidateTableCellView()
            cell?.identifier = cellIdentifier
        }

        if let cell = cell {
            configureCellView(cell, forRow: row)
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("CandidateRowView")
        var rowView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableRowView

        if rowView == nil {
            rowView = NSTableRowView()
            rowView?.identifier = identifier
        }

        return rowView
    }
}

import Foundation

enum FinderMenuAction: String {
    case cutSelection
    case moveCutItemsHere
    case moveSelectionToChosenFolder
    case copySelectedPaths
    case copyTargetedPath
    case openTerminalForSelection
    case openTerminalHere
    case clearCutBuffer
    case openSettings
}

struct FinderMenuItemSpec: Equatable {
    let title: String
    let action: FinderMenuAction
    let enabled: Bool
    let symbolName: String?
}

/// Pure menu construction logic, kept independent from AppKit so it can be unit tested.
enum MenuModel {
    static func itemsMenu(selectedCount: Int, cutCount: Int) -> [FinderMenuItemSpec] {
        guard selectedCount > 0 else { return [] }

        var items: [FinderMenuItemSpec] = [
            FinderMenuItemSpec(
                title: "剪切（准备移动）",
                action: .cutSelection,
                enabled: true,
                symbolName: "scissors"
            )
        ]

        if cutCount > 0 && selectedCount == 1 {
            items.append(
                FinderMenuItemSpec(
                    title: "移动 \(cutCount) 项到此文件夹",
                    action: .moveCutItemsHere,
                    enabled: true,
                    symbolName: "tray.and.arrow.down"
                )
            )
        }

        items.append(
            FinderMenuItemSpec(
                title: "移动到文件夹…",
                action: .moveSelectionToChosenFolder,
                enabled: true,
                symbolName: "folder"
            )
        )
        items.append(
            FinderMenuItemSpec(
                title: "复制绝对路径",
                action: .copySelectedPaths,
                enabled: true,
                symbolName: "doc.on.doc"
            )
        )
        if selectedCount == 1 {
            items.append(
                FinderMenuItemSpec(
                    title: "在终端中打开",
                    action: .openTerminalForSelection,
                    enabled: true,
                    symbolName: "terminal"
                )
            )
        }
        return items
    }

    static func containerMenu(cutCount: Int, hasTargetedURL: Bool) -> [FinderMenuItemSpec] {
        var items: [FinderMenuItemSpec] = []

        if cutCount > 0 {
            items.append(
                FinderMenuItemSpec(
                    title: "移动 \(cutCount) 项到这里",
                    action: .moveCutItemsHere,
                    enabled: hasTargetedURL,
                    symbolName: "tray.and.arrow.down"
                )
            )
            items.append(
                FinderMenuItemSpec(
                    title: "取消待移动（\(cutCount) 项）",
                    action: .clearCutBuffer,
                    enabled: true,
                    symbolName: "xmark.circle"
                )
            )
        } else {
            items.append(
                FinderMenuItemSpec(
                    title: "移动到这里（暂无待移动项目）",
                    action: .moveCutItemsHere,
                    enabled: false,
                    symbolName: "tray.and.arrow.down"
                )
            )
        }

        items.append(
            FinderMenuItemSpec(
                title: "复制当前目录路径",
                action: .copyTargetedPath,
                enabled: hasTargetedURL,
                symbolName: "doc.on.doc"
            )
        )
        items.append(
            FinderMenuItemSpec(
                title: "在终端中打开当前目录",
                action: .openTerminalHere,
                enabled: hasTargetedURL,
                symbolName: "terminal"
            )
        )
        items.append(
            FinderMenuItemSpec(
                title: "SuperFinder 设置…",
                action: .openSettings,
                enabled: true,
                symbolName: "gearshape"
            )
        )
        return items
    }
}

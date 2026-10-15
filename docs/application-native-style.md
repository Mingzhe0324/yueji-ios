# Application-wide native style audit

Update: [Visible motion](visible-motion.md) adds an explicit system zoom only for Overview/Ledger expense-card navigation, plus scoped month/item-list and banner entrance animations. Editor sheets retain the interaction ownership described here.

The app uses system navigation stacks, tab bars, menus, pickers, dialogs, keyboard transitions and sheet presentation. These adopt the platform design through the installed OS and build SDK. Keep native interaction ownership rather than adding custom navigation zooms, sheet offsets or global animation transactions. Glass is reserved for floating actions/navigation and foreground notification cards; financial content stays on readable grouped backgrounds.

This audit brings the remaining production List/Form pages onto the shared `yuejiListSurface`: recurring editing, duplicate review, refunds, friend summary, fuel calculation, merchant rules, restore preview, category management/editing, monthly comparison, filtering, bank setup, receipt splitting and the three bank notification/detail/review forms. Existing overview, ledger, settings, friends/settlements, savings lists and reimbursement pages already use that shared surface. Duplicate application of the surface on comparison/export is removed.

Recurring/category/repayment Save, filter Apply and savings Confirm use the same native prominent button policy as expense/item/reimbursement editing, including the opaque fallback for Reduce Transparency. SaveActionLabel delegates to EditorSaveLabel so its text keeps its size while the progress indicator overlays it. Text uses default system tracking. Amount labels retain numeric transitions only when values change, removing the unnecessary on-appearance state mutation and optional entrance transform.

Savings editing and receipt comparison now receive shared sheet appearance; inbox, notification destination and both usage-guide presentations also receive it. Receipt comparison's ScrollView uses the shared page/scroll-edge policy. The native camera/Photos picker keeps its platform presentation. Settlement result and notification-status updates use the existing shared restrained motion timing. Accessibility Reduce Motion/Reduce Transparency and user-selected light/dark appearance remain in effect.

No money calculations, reporting semantics, keyboard focus identities, item picker rows, draft confirmation, notification dismissal logic or CI stages/timeouts are changed by this audit. Existing financial/transaction/gesture regression tests remain required. Branding, illustrations and guide examples remain app content while their enclosing navigation/presentation uses system components.

Validation: project/reference integrity, Swift syntax across all app sources and diff formatting on Windows. Native compilation, UI regressions and physical-device visual/performance verification remain pending. This does not establish an exact frame-rate or pixel-match guarantee.

Reference: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass

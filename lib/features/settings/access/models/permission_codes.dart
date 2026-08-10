/// Central permission identifiers used by routes and write actions.
abstract final class PermissionCodes {
  static const usersView = 'users.view';
  static const usersCreate = 'users.create';
  static const usersUpdate = 'users.update';
  static const usersDelete = 'users.delete';

  static const reportsView = 'reports.view';
  static const reportsExport = 'reports.export';
  static const settingsView = 'settings.view';
  static const settingsBackup = 'settings.backup';
  static const settingsRestore = 'settings.restore';
  static const recycleBinView = 'settings.recycle_bin.view';
  static const recycleBinRestore = 'settings.recycle_bin.restore';
  static const recycleBinPurge = 'settings.recycle_bin.purge';

  static const approvalsView = 'approvals.view';
  static const approvalsDecide = 'approvals.decide';
  static const periodsView = 'periods.view';
  static const periodsClose = 'periods.close';
  static const periodsReopen = 'periods.reopen';
  static const auditView = 'audit.view';
  static const permissionScopesManage = 'permissions.scopes.manage';

  static const salesApprove = 'sales.approve';
  static const salesCancel = 'sales.cancel';
  static const purchasesApprove = 'purchases.approve';
  static const purchasesCancel = 'purchases.cancel';
  static const maintenanceApprove = 'maintenance.approve';
  static const maintenanceCancel = 'maintenance.cancel';
  static const accountingPost = 'accounting.post';
  static const accountingReverse = 'accounting.reverse';
  static const inventoryTransfer = 'inventory.transfer';
  static const inventoryTransferDelete = 'inventory.transfer.delete';
  static const carsTransferDelete = 'cars.transfer.delete';
  static const inventoryAdjust = 'inventory.adjust';
  static const inventoryReceive = 'inventory.receive';
  static const inventoryIssue = 'inventory.issue';
  static const cashboxReceipt = 'cashbox.receipt';
  static const cashboxPayment = 'cashbox.payment';

  static String view(String module) => '$module.view';
  static String create(String module) => '$module.create';
  static String update(String module) => '$module.update';
  static String delete(String module) => '$module.delete';
}

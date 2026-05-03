/* 
@description       : Controller for AccountProjectList LWC
@author            : Sai Keerthi N
@created date      : 05/01/2026
 */
public with sharing class AccountProjectListController {
    private static final Integer MIN_PAGE_SIZE = 1;
    
    private static final Integer MAX_PAGE_SIZE = 1000;

    /** each row in the Account project list. */
    public class ProjectListRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal budget;
        @AuraEnabled public Datetime createdDate;
    }

    /** Result of starting a query cursor: total count of matching projects + serialized cursor for paging. */
    public class ProjectsCursorInitResult {
        @AuraEnabled public Integer totalMatchingCount;
        @AuraEnabled public String apexCursor;
    }

    /**
     *@param accountId - the account id
     *@param statusFilter - the status filter
     *@param activeOnly - whether to only include active projects
     *@return the result of starting a query cursor
     @description starts a query cursor for the account projects
     */
    @AuraEnabled
    public static ProjectsCursorInitResult initProjectsCursor(Id accountId, String statusFilter, Boolean activeOnly) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        Boolean onlyActive = activeOnly == true;
        String statusKey = (String.isBlank(statusFilter) || statusFilter == 'All') ? null : statusFilter;

        String whereClause = buildWhereClause(accountId, onlyActive, statusKey);
        Integer total = Database.countQuery('SELECT COUNT() FROM Project__c WHERE ' + whereClause);

        String selectSoql =
            'SELECT Id, Name, Status__c, Budget__c, CreatedDate FROM Project__c WHERE ' +
            whereClause +
            ' ORDER BY CreatedDate DESC, Id DESC';//descending order by CreatedDate and Id (deterministic order)

        Database.Cursor locator = Database.getCursor(selectSoql);

        ProjectsCursorInitResult initResult = new ProjectsCursorInitResult();
        initResult.totalMatchingCount = total;
        initResult.apexCursor = JSON.serialize(locator);
        return initResult;
    }

    /**
     * @param startIndex - the index of the first row to fetch
     * @param pageSize - the number of rows to fetch
     * @param apexCursor - the serialized cursor
     * @param totalRowCount - the total number of rows in the query
     * @return the list of projects
     @description fetches a slice of projects from the cursor
     */
    @AuraEnabled
    public static List<ProjectListRow> fetchProjectsByCursor(
        Integer startIndex,
        Integer pageSize,
        String apexCursor,
        Integer totalRowCount
    ) {
        if (String.isBlank(apexCursor)) {
            throw new AuraHandledException('Cursor is required.');
        }

        Integer ps = pageSize == null ? 10 : pageSize;
        if (ps < MIN_PAGE_SIZE || ps > MAX_PAGE_SIZE) {
            throw new AuraHandledException('Page size must be between ' + MIN_PAGE_SIZE + ' and ' + MAX_PAGE_SIZE + '.');
        }

        Integer start = startIndex == null ? 0 : startIndex;
        if (start < 0) {
            throw new AuraHandledException('startIndex cannot be negative.');
        }

        if (totalRowCount != null && totalRowCount >= 0 && start >= totalRowCount) {
            return new List<ProjectListRow>();
        }

        Database.Cursor locator;
        try {
            locator = (Database.Cursor) JSON.deserialize(apexCursor, Database.Cursor.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid or expired cursor. Refresh the list.');
        }

        Integer fetchCount = ps;
        if (totalRowCount != null && totalRowCount >= 0) {
            Integer remaining = totalRowCount - start;
            if (remaining <= 0) {
                return new List<ProjectListRow>();
            }
            if (fetchCount > remaining) {
                fetchCount = remaining;
            }
        }

        try {
            List<Project__c> slice = (List<Project__c>) locator.fetch(start, fetchCount);//fetch the slice of projects from the cursor
            return toRows(slice);//convert the projects to the list of rows
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to load this page. Refresh filters or try again. ' + e.getMessage()
            );
        }
    }

    private static String buildWhereClause(Id accountId, Boolean onlyActive, String statusKey) {
        String w = 'Account__c = \'' + String.valueOf(accountId) + '\'';
        if (onlyActive) {
            w += ' AND Status__c = \'Active\'';
        } else if (String.isNotBlank(statusKey)) {
            w += ' AND Status__c = \'' + statusKey + '\'';
        }
        return w;
    }

    private static List<ProjectListRow> toRows(List<Project__c> projects) {
        List<ProjectListRow> rows = new List<ProjectListRow>();
        for (Project__c p : projects) {
            ProjectListRow r = new ProjectListRow();
            r.id = p.Id;
            r.name = p.Name;
            r.status = p.Status__c;
            r.budget = p.Budget__c;
            r.createdDate = p.CreatedDate;
            rows.add(r);
        }
        return rows;
    }
}
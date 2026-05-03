/**
 * Tests for AccountProjectListController - cursor initialization, paging validation,
 * LWC row model, cursor init result, filters, and large-volume (>1000) fetches.
 */
@IsTest
private class AccountProjectListControllerTest {
    private static final Integer BULK_PROJECT_COUNT = 1050;

    private static Account createTestAccount() {
        Account acc = new Account(Name = 'Bulk Ctrl Test ' + String.valueOf(Math.abs(Crypto.getRandomLong())));
        insert acc;
        return acc;
    }

    //Chunked inserts to stay within heap/DML patterns and invoke trigger in batches 
    private static void insertProjects(Id accountId, Integer totalCount, String status, Decimal budgetWhenActive) {
        List<Project__c> batch = new List<Project__c>();
        for (Integer i = 0; i < totalCount; i++) {
            Project__c p = new Project__c(Account__c = accountId, Status__c = status);
            if (status == 'Active') {
                p.Budget__c = budgetWhenActive != null ? budgetWhenActive : 100;
            }
            batch.add(p);
            if (batch.size() == 200) {
                insert batch;
                batch.clear();
            }
        }
        if (!batch.isEmpty()) {
            insert batch;
        }
    }

    private static AccountProjectListController.ProjectsCursorInitResult initCursor(
        Id accountId,
        String statusFilter,
        Boolean activeOnly
    ) {
        return AccountProjectListController.initProjectsCursor(accountId, statusFilter, activeOnly);
    }

    // initProjectsCursor tests

    //null account id test
    @IsTest
    static void initProjectsCursor_nullAccountId_throwsAuraHandled() {
        Boolean threw = false;
        try {
            initCursor(null, null, false);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Expected AuraHandledException for null account Id (message may be generic in tests).');
    }

    //no projects test
    @IsTest
    static void initProjectsCursor_noProjects_returnsZeroCountAndCursor() {
        Account acc = createTestAccount();

        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, 'All', false);

        Assert.areEqual(0, cursorInit.totalMatchingCount, 'Total matching count must be 0.');
        Assert.isTrue(String.isNotBlank(cursorInit.apexCursor), 'Serialized cursor must not be blank.');
    }

    //all statuses test
    @IsTest
    static void initProjectsCursor_countsAllStatuses_whenNoFilter() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 2, 'Planned', null);
        insertProjects(acc.Id, 3, 'Active', 50);
        insertProjects(acc.Id, 1, 'Completed', null);

        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        Assert.areEqual(6, cursorInit.totalMatchingCount, 'Total matching count must be 6.');
        Assert.isTrue(String.isNotBlank(cursorInit.apexCursor), 'Apex cursor must not be blank.');
    }

    //all statuses test with blank filter
    @IsTest
    static void initProjectsCursor_allStatus_sameAsBlankFilter() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 4, 'Planned', null);

        Integer blankTotal = initCursor(acc.Id, '', false).totalMatchingCount;
        Integer allTotal = initCursor(acc.Id, 'All', false).totalMatchingCount;
        Integer nullTotal = initCursor(acc.Id, null, false).totalMatchingCount;

        Assert.areEqual(4, blankTotal, 'Blank total must be 4.');
        Assert.areEqual(blankTotal, allTotal, 'Blank total must be equal to all total.');
        Assert.areEqual(blankTotal, nullTotal, 'Blank total must be equal to null total.');
    }

    //active only test
    @IsTest
    static void initProjectsCursor_activeOnly_countsActiveOnly() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 5, 'Planned', null);
        insertProjects(acc.Id, 2, 'Active', 75);

        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, true);

        Assert.areEqual(2, cursorInit.totalMatchingCount, 'Total matching count must be 2.');
    }

    //active only test with null treated as false
    @IsTest
    static void initProjectsCursor_activeOnly_nullTreatedAsFalse() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 1, 'Active', 10);

        Assert.areEqual(1, initCursor(acc.Id, null, null).totalMatchingCount, 'Total matching count must be 1.');
    }

    //status filter test
    @IsTest
    static void initProjectsCursor_statusFilter_plannedAndCompleted() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 3, 'Planned', null);
        insertProjects(acc.Id, 2, 'Active', 20);
        insertProjects(acc.Id, 4, 'Completed', null);

        Assert.areEqual(3, initCursor(acc.Id, 'Planned', false).totalMatchingCount, 'Total matching count must be 3.');
        Assert.areEqual(4, initCursor(acc.Id, 'Completed', false).totalMatchingCount, 'Total matching count must be 4.');
    }

    // fetchProjectsByCursor tests

    //blank cursor test
    @IsTest
    static void fetchProjectsByCursor_blankCursor_throwsAuraHandled() {
        Boolean threw = false;
        try {
            AccountProjectListController.fetchProjectsByCursor(0, 10, '   ', 100);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Expected AuraHandledException for blank cursor.');
    }

    //page size too small test
    @IsTest
    static void fetchProjectsByCursor_pageSizeTooSmall_throwsAuraHandled() {
        Account acc = createTestAccount();
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        Boolean threw = false;
        try {
            AccountProjectListController.fetchProjectsByCursor(0, 0, cursorInit.apexCursor, 0);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Expected AuraHandledException for page size too small.');
    }

    //page size too large test
    @IsTest
    static void fetchProjectsByCursor_pageSizeTooLarge_throwsAuraHandled() {
        Account acc = createTestAccount();
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        Boolean threw = false;
        try {
            AccountProjectListController.fetchProjectsByCursor(0, 1001, cursorInit.apexCursor, 0);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Expected AuraHandledException for page size too large.');
    }

    //negative start index test
    @IsTest
    static void fetchProjectsByCursor_negativeStart_throwsAuraHandled() {
        Account acc = createTestAccount();
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        Boolean threw = false;
        try {
            AccountProjectListController.fetchProjectsByCursor(-1, 10, cursorInit.apexCursor, 10);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Expected AuraHandledException for negative start index.');
    }

    //start at or beyond total test
    @IsTest
    static void fetchProjectsByCursor_startAtOrBeyondTotal_returnsEmptyWithoutFetch() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 3, 'Planned', null);
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        List<AccountProjectListController.ProjectListRow> atExact =
            AccountProjectListController.fetchProjectsByCursor(3, 100, cursorInit.apexCursor, 3);
        List<AccountProjectListController.ProjectListRow> pastEnd =
            AccountProjectListController.fetchProjectsByCursor(10, 100, cursorInit.apexCursor, 3);

        Assert.isTrue(atExact.isEmpty(), 'startIndex == totalRowCount must produce empty list.');
        Assert.isTrue(pastEnd.isEmpty(), 'startIndex > totalRowCount must produce empty list.');
    }

    //invalid cursor test
    @IsTest
    static void fetchProjectsByCursor_invalidCursor_throwsAuraHandled() {
        Boolean threw = false;
        try {
            AccountProjectListController.fetchProjectsByCursor(0, 10, '{"not":"aCursor"}', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Expected AuraHandledException for invalid cursor.');
    }

    //null page size test
    @IsTest
    static void fetchProjectsByCursor_nullPageSize_defaultsTen_nullStart_defaultsZero() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 15, 'Completed', null);
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        List<AccountProjectListController.ProjectListRow> rows =
            AccountProjectListController.fetchProjectsByCursor(
                null,
                null,
                cursorInit.apexCursor,
                cursorInit.totalMatchingCount
            );

        Assert.areEqual(10, rows.size(), 'Default page size should be 10.');
        for (AccountProjectListController.ProjectListRow r : rows) {
            Assert.isNotNull(r.id, 'Id must be not null.');
            Assert.isNotNull(r.name, 'Name must be not null.');
            Assert.areEqual('Completed', r.status, 'Status must be Completed.');
        }
    }

    //boundary page sizes test
    @IsTest
    static void fetchProjectsByCursor_boundaryPageSizes_allowed() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 2, 'Planned', null);
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        List<AccountProjectListController.ProjectListRow> one =
            AccountProjectListController.fetchProjectsByCursor(0, 1, cursorInit.apexCursor, cursorInit.totalMatchingCount);
        List<AccountProjectListController.ProjectListRow> max =
            AccountProjectListController.fetchProjectsByCursor(
                0,
                1000,
                cursorInit.apexCursor,
                cursorInit.totalMatchingCount
            );

        Assert.areEqual(1, one.size(), 'Fetch count must hold to rows remaining.');
        Assert.areEqual(2, max.size(), 'Fetch count must hold to rows remaining.');
    }

    //holds last page test
    @IsTest
    static void fetchProjectsByCursor_holdsLastPage_whenRemainingLessThanPageSize() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 5, 'Planned', null);
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        List<AccountProjectListController.ProjectListRow> rows =
            AccountProjectListController.fetchProjectsByCursor(
                0,
                1000,
                cursorInit.apexCursor,
                cursorInit.totalMatchingCount
            );

        Assert.areEqual(5, rows.size(), 'Fetch count must hold to rows remaining.');
    }

    //maps budget and active status test
    @IsTest
    static void fetchProjectsByCursor_mapsBudgetAndActiveStatus() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 1, 'Active', 123.45);

        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);
        List<AccountProjectListController.ProjectListRow> rows =
            AccountProjectListController.fetchProjectsByCursor(
                0,
                10,
                cursorInit.apexCursor,
                cursorInit.totalMatchingCount
            );

        Assert.areEqual(1, rows.size(), 'Fetch count must hold to rows remaining.');
        Assert.areEqual('Active', rows[0].status, 'Status must be Active.');
        Assert.areEqual(123.45, rows[0].budget, 'Budget must be 123.45.');
        Assert.isNotNull(rows[0].createdDate, 'Created date must be not null.');
    }

    /**
     * Without totalRowCount the controller does not hold the page size; Cursor.fetch throws if
     * pageSize exceeds rows at that position. Page size must stay within the actual row count.
     */
    @IsTest
    static void fetchProjectsByCursor_withoutTotalRowCount_pageSizeWithinRowCount_returnsRows() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, 4, 'Planned', null);
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        List<AccountProjectListController.ProjectListRow> rows =
            AccountProjectListController.fetchProjectsByCursor(0, 4, cursorInit.apexCursor, null);

        Assert.areEqual(4, rows.size(), 'Fetch count must hold to rows remaining.');
    }

    // bulk test: > 1000 records

    @IsTest
    static void bulk_fetchBeyondOneThousand_countMatchesAndPagesDoNotOverlap() {
        Account acc = createTestAccount();
        insertProjects(acc.Id, BULK_PROJECT_COUNT, 'Planned', null);

        Test.startTest();
        AccountProjectListController.ProjectsCursorInitResult cursorInit = initCursor(acc.Id, null, false);

        Assert.areEqual(BULK_PROJECT_COUNT, cursorInit.totalMatchingCount);
        Assert.isTrue(String.isNotBlank(cursorInit.apexCursor));

        List<AccountProjectListController.ProjectListRow> page1 =
            AccountProjectListController.fetchProjectsByCursor(
                0,
                1000,
                cursorInit.apexCursor,
                cursorInit.totalMatchingCount
            );
        List<AccountProjectListController.ProjectListRow> page2 =
            AccountProjectListController.fetchProjectsByCursor(
                1000,
                1000,
                cursorInit.apexCursor,
                cursorInit.totalMatchingCount
            );
        Test.stopTest();

        Assert.areEqual(1000, page1.size(), 'First page should be full (1000 rows).');
        Assert.areEqual(50, page2.size(), 'Second page should return remaining 50 rows.');

        Set<Id> seen = new Set<Id>();
        for (AccountProjectListController.ProjectListRow r : page1) {
            Assert.isNotNull(r.id);
            Assert.areEqual('Planned', r.status);
            seen.add(r.id);
        }
        for (AccountProjectListController.ProjectListRow r : page2) {
            Assert.isFalse(seen.contains(r.id), 'Paged results must not repeat Ids.');
            seen.add(r.id);
        }
        Assert.areEqual(BULK_PROJECT_COUNT, seen.size(), 'Combined pages must cover all records.');
    }
}
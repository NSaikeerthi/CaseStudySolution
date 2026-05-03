/**
 * @description Covers projectTrigger -> projectTriggerHanlder rollup of Account.Total_Projects__c:
 * insert, delete, undelete, after update (handleAfterUpdate), re-parent, bulk insert (200/500), bulk update re-parent (500), bulk mixed update (500), null Account, non-parent updates, clear/set lookup.
 * Each test wraps the primary DML under Test.startTest/stopTest so limits reset for the code under test.
 * After DML that fires the rollup trigger, use refreshAccountTotals(Id)-accA() alone does not refresh Total_Projects__c in memory.
 */
@IsTest
private class projectTriggerHandlerTest {
    private static final String ACC_A_NAME = 'Test Account A';
    private static final String ACC_B_NAME = 'Test Account B';

    /**
     * @description       : This method is used to setup the data for the test.
     */
    @TestSetup
    static void setupData() {
        insert new List<Account>{
            new Account(Name = ACC_A_NAME),
            new Account(Name = ACC_B_NAME)
        };
    }

    private static Account accA() {
        return [SELECT Id, Total_Projects__c FROM Account WHERE Name = :ACC_A_NAME LIMIT 1];
    }

    private static Account accB() {
        return [SELECT Id, Total_Projects__c FROM Account WHERE Name = :ACC_B_NAME LIMIT 1];
    }

    /**
     * Trigger updates Total_Projects__c in the database, any Account instance loaded earlier (e.g. from accA()) is stored in memory until re-queried.
     */
    private static Account refreshAccountTotals(Id accountId) {
        return [SELECT Id, Total_Projects__c FROM Account WHERE Id = :accountId LIMIT 1];
    }

    /**
     * @description       : This method is used to create a project.
     * @param accountId   : The account id
     * @param status      : The status of the project
     * @return            : The project
     */
    private static Project__c project(Id accountId, String status) {
        Project__c p = new Project__c();
        if (accountId != null) {
            p.Account__c = accountId;
        }
        if (String.isNotBlank(status)) {
            p.Status__c = status;
        }
        return p;
    }

    /**
     * This method is used to test the project insert and increment the total count on the linked accounts.
     */
    @IsTest
    static void insert_IncrementsTotalCount_OnLinkedAccounts() {
        Account a = accA();
        Account b = accB();

        Test.startTest();
        insert new List<Project__c>{
            project(a.Id, 'Planned'),
            project(a.Id, 'Planned'),
            project(b.Id, 'Completed')
        };
        Test.stopTest();

        Map<Id, Account> refreshed = new Map<Id, Account>(
            [SELECT Id, Total_Projects__c FROM Account WHERE Id IN :new Set<Id>{ a.Id, b.Id }]
        );
        System.assertEquals(2, refreshed.get(a.Id).Total_Projects__c, 'Account A should count two Projects.');
        System.assertEquals(1, refreshed.get(b.Id).Total_Projects__c, 'Account B should count one Project.');
    }

    /**
     * Insert with Active + positive budget so DML succeeds if org metadata requires budget for Active.
     * We only assert rollup (Total_Projects__c)
     */
    @IsTest
    static void insert_ActiveWithPositiveBudget_ValidationAndTotalCountUpdate() {
        Account a = accA();
        Project__c p = new Project__c(
            Account__c = a.Id,
            Status__c = 'Active',
            Budget__c = 100
        );
        Test.startTest();
        insert p;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(1, a.Total_Projects__c, 'Total count should be 1.');
    }

    /**
     * This method is used to test the project delete and decrement the total count on the linked accounts.
     */
    @IsTest
    static void delete_Decrements_And_TotalCountUpdate() {
        Account a = accA();
        Project__c p = project(a.Id, 'Planned');
        insert p;

        a = refreshAccountTotals(a.Id);
        System.assertEquals(1, a.Total_Projects__c, 'Total count should be 1.');

        Test.startTest();
        delete p;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(0, a.Total_Projects__c, 'Total should be 0 when no Projects remain.');
    }

    /**
     * Ensures projectTrigger (after update) invokes projectTriggerHanlder.run() when Trigger.isUpdate and handleAfterUpdate is called  .
     * Single-record update with Account__c change so the handler recalculates both old and new parent Accounts.
     */
    @IsTest
    static void afterUpdate_HandleAfterUpdate_RecalculatesWhenAccountChanges() {
        Account a = accA();
        Account b = accB();

        Project__c p = project(a.Id, 'Planned');
        insert p;

        System.assertEquals(1, refreshAccountTotals(a.Id).Total_Projects__c);
        System.assert(
            refreshAccountTotals(b.Id).Total_Projects__c == null || refreshAccountTotals(b.Id).Total_Projects__c == 0,
            'B not linked yet.'
        );

        p = [SELECT Id, Account__c FROM Project__c WHERE Id = :p.Id];
        p.Account__c = b.Id;

        Test.startTest();
        update p;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        b = refreshAccountTotals(b.Id);
        System.assertEquals(0, a.Total_Projects__c, 'A should have no Projects after re-parent.');
        System.assertEquals(1, b.Total_Projects__c, 'B should count the re-parented Project.');
    }

    /**
     * This method is used to test the project undelete and restore the total count on the linked accounts.
     */
    @IsTest
    static void undelete_RestoresTotal() {
        Account a = accA();
        Project__c p = project(a.Id, 'Planned');
        insert p;

        delete p;
        a = refreshAccountTotals(a.Id);
        System.assertEquals(0, a.Total_Projects__c, 'Total count should be 0.');

        Test.startTest();
        undelete p;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(1, a.Total_Projects__c, 'Total count should be 1.');
    }

    /**
     *This method is used to test the project re-parent and adjust the total count on the linked accounts.
     */
    @IsTest
    static void update_Reparent_AdjustsOldAndNewAccount() {
        Account a = accA();
        Account b = accB();

        Project__c p1 = project(a.Id, 'Planned');
        Project__c p2 = project(a.Id, 'Planned');
        insert new List<Project__c>{ p1, p2 };

        Map<Id, Account> accountsBeforeUpdate = new Map<Id, Account>(
            [SELECT Id, Total_Projects__c FROM Account WHERE Id IN :new Set<Id>{ a.Id, b.Id }]
        );
        System.assertEquals(2, accountsBeforeUpdate.get(a.Id).Total_Projects__c, 'Total count should be 2.');
        System.assert(
            accountsBeforeUpdate.get(b.Id).Total_Projects__c == null || accountsBeforeUpdate.get(b.Id).Total_Projects__c == 0,
            'Account B has no Projects yet (field may be null until rollup writes it).'
        );

        p1.Account__c = b.Id;
        Test.startTest();
        update p1;
        Test.stopTest();

        Map<Id, Account> accountsAfterUpdate = new Map<Id, Account>(
            [SELECT Id, Total_Projects__c FROM Account WHERE Id IN :new Set<Id>{ a.Id, b.Id }]
        );
        System.assertEquals(1, accountsAfterUpdate.get(a.Id).Total_Projects__c, 'Total count should be 1.');
        System.assertEquals(1, accountsAfterUpdate.get(b.Id).Total_Projects__c, 'Total count should be 1.');
    }

    /**
     *This method is used to test the project clear account and decrement the total count on the linked accounts.
     */
    @IsTest
    static void update_ClearAccount_Decrements_CorrectTotalCount() {
        Account a = accA();
        Project__c p = project(a.Id, 'Planned');
        insert p;

        a = refreshAccountTotals(a.Id);
        System.assertEquals(1, a.Total_Projects__c, 'Total count should be 1.');

        p.Account__c = null;
        Test.startTest();
        update p;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(0, a.Total_Projects__c, 'Total count should be 0.');
    }

    /**
     *This method is used to test the project set account from null and increment the total count on the linked accounts.
     */
    @IsTest
    static void update_SetAccountFromNull_IncrementsTarget() {
        Account a = accA();
        Project__c p = project(null, 'Planned');
        insert p;

        a = refreshAccountTotals(a.Id);
        System.assert(
            a.Total_Projects__c == null || a.Total_Projects__c == 0,
            'No Project linked to A yet; rollup has not updated this Account (field may stay null).'
        );

        p.Account__c = a.Id;
        Test.startTest();
        update p;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(1, a.Total_Projects__c, 'Total count should be 1.');
    }

    /**
     * This method is used to test the project update apart from account lookup and 
     * does not reset/update the total count on the linked accounts.
     */
    @IsTest
    static void update_NonLookupFieldOnly_DoesNotResetTotalCount() {
        Account a = accA();
        insert new List<Project__c>{
            project(a.Id, 'Planned'),
            project(a.Id, 'Planned')
        };
        a = refreshAccountTotals(a.Id);
        System.assertEquals(2, a.Total_Projects__c, 'Total count should be 2.');

        Project__c toUpdate = [SELECT Id, Status__c FROM Project__c WHERE Account__c = :a.Id LIMIT 1];
        toUpdate.Status__c = 'Completed';
        
        Test.startTest();
        update toUpdate;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(2, a.Total_Projects__c, 'Account__c unchanged, total must remain 2.');
    }

    /**
     * This method is used to test the project insert without account and 
     * does not fail and does not fire the total count update as expected.
     */
    @IsTest
    static void insert_NoAccount_DoesNotFail_AndDoesNotFireAccountTotals() {
        Account a = accA();
        Project__c projectWithoutAccount = project(null, 'Planned');
        Test.startTest();
        insert projectWithoutAccount;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(
            true,
            a.Total_Projects__c == null || a.Total_Projects__c == 0,
            'Project without Account should not fire Account totals update.'
        );
    }

    /**
     * This method is used to test the project bulk insert and set the total count on the linked accounts.
     */
    @IsTest
    static void bulkInsert_200_SetsTotalCorrectly() {
        Account a = accA();
        List<Project__c> batch = new List<Project__c>();
        for (Integer i = 0; i < 200; i++) {
            batch.add(project(a.Id, 'Planned'));
        }
        Test.startTest();
        insert batch;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(200, a.Total_Projects__c, 'Total count should be 200.');
    }

    /**
     * Single DML of 500 rows, total count should be 500.
     */
    @IsTest
    static void bulkInsert_500_SetsTotalCorrectly() {
        Account a = accA();
        List<Project__c> batch = new List<Project__c>();
        for (Integer i = 0; i < 500; i++) {
            batch.add(project(a.Id, 'Planned'));
        }
        Test.startTest();
        insert batch;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        System.assertEquals(500, a.Total_Projects__c, 'Total count should be 500.');
    }

    /**
     * Single update DML on 500 Projects (re-parent A to B); both Accounts must reflect correct totals after update.
     */
    @IsTest
    static void bulkUpdate_500_ReparentFromAToB() {
        Account a = accA();
        Account b = accB();

        List<Project__c> batch = new List<Project__c>();
        for (Integer i = 0; i < 500; i++) {
            batch.add(project(a.Id, 'Planned'));
        }
        insert batch;

        Map<Id, Account> before = new Map<Id, Account>(
            [SELECT Id, Total_Projects__c FROM Account WHERE Id IN :new Set<Id>{ a.Id, b.Id }]
        );
        System.assertEquals(500, before.get(a.Id).Total_Projects__c);
        System.assert(
            before.get(b.Id).Total_Projects__c == null || before.get(b.Id).Total_Projects__c == 0,
            'B has no Projects yet (Total_Projects__c may be null).'
        );

        for (Project__c p : batch) {
            p.Account__c = b.Id;
        }

        Test.startTest();
        update batch;
        Test.stopTest();

        Map<Id, Account> after = new Map<Id, Account>(
            [SELECT Id, Total_Projects__c FROM Account WHERE Id IN :new Set<Id>{ a.Id, b.Id }]
        );
        System.assertEquals(0, after.get(a.Id).Total_Projects__c, 'Old parent should lose all Projects.');
        System.assertEquals(500, after.get(b.Id).Total_Projects__c, 'New parent should reflect all 500.');
    }

    /**
     * Mixed bulk update (500 rows in one DML): 200 stay on A, 200 re-parent to B, 100 clear Account__c.
     * Verifies handler aggregates all touched Accounts (old + new) in one transaction.
     */
    @IsTest
    static void bulkUpdate_500_MixedStayReparentAndClearAccount() {
        Account a = accA();
        Account b = accB();

        List<Project__c> batch = new List<Project__c>();
        for (Integer i = 0; i < 500; i++) {
            batch.add(project(a.Id, 'Planned'));
        }
        insert batch;

        Map<Id, Account> before = new Map<Id, Account>(
            [SELECT Id, Total_Projects__c FROM Account WHERE Id IN :new Set<Id>{ a.Id, b.Id }]
        );
        System.assertEquals(500, before.get(a.Id).Total_Projects__c);
        System.assert(
            before.get(b.Id).Total_Projects__c == null || before.get(b.Id).Total_Projects__c == 0,
            'B has no Projects yet (Total_Projects__c may be null).'
        );

        for (Integer i = 0; i < 500; i++) {
            if (i >= 200 && i < 400) {
                batch[i].Account__c = b.Id;
            } else if (i >= 400) {
                batch[i].Account__c = null;
            }
        }

        Test.startTest();
        update batch;
        Test.stopTest();

        a = refreshAccountTotals(a.Id);
        b = refreshAccountTotals(b.Id);
        System.assertEquals(200, a.Total_Projects__c, 'A keeps 200, 200 moved to B and 100 unlinked.');
        System.assertEquals(200, b.Total_Projects__c, 'B receives 200 re-parented Projects.');
    }
}
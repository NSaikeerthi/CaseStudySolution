/**
 * @author            : Sai Keerthi N
 * @created date      : 05/01/2026
 * Description         : This class is used to handle the project trigger.
*/
public without sharing class projectTriggerHandler {
    private static Boolean isRunning = false;

    public static void run() {
        if (isRunning) return;//prevent recursive calls to avoid infinite loop if occurs by some other trigger or code
        isRunning = true;
        if (Trigger.isInsert || Trigger.isUndelete) {
            handleAfterInsertOrUndelete((List<Project__c>) Trigger.new);
        }
        if (Trigger.isDelete) {
            handleAfterDelete((List<Project__c>) Trigger.old);
        }
        if (Trigger.isUpdate) {
                handleAfterUpdate((List<Project__c>) Trigger.new, (Map<Id, Project__c>) Trigger.oldMap);
        }
    
        isRunning = false;
    }

    /**
     * @description       : This method is used to handle the after insert or undelete event.
     * @param newList     : List of new projects
     */
    private static void handleAfterInsertOrUndelete(List<Project__c> newList) {
        Set<Id> accountIds = new Set<Id>();
        for (Project__c p : newList) {
            if (p.Account__c != null) accountIds.add(p.Account__c);
        }
        updateCounts(accountIds);
    }

    /**
     * @description       : This method is used to handle the after delete event.
     * @param oldList     : List of old projects
     */
    private static void handleAfterDelete(List<Project__c> oldList) {
        Set<Id> accountIds = new Set<Id>();
        for (Project__c p : oldList) {
            if (p.Account__c != null) accountIds.add(p.Account__c);
        }
        updateCounts(accountIds);
    }

    /**
     * @description       : This method is used to handle the after update event.
     * @param newList     : List of new projects
     * @param oldMap      : Map of old projects
     */
    private static void handleAfterUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        Set<Id> accountIds = new Set<Id>();

        for (Project__c pNew : newList) {
            Project__c pOld = oldMap.get(pNew.Id);
            Id oldAccId = (pOld == null) ? null : pOld.Account__c;
            Id newAccId = pNew.Account__c;

            if (oldAccId == newAccId) continue;

            if (oldAccId != null) accountIds.add(oldAccId);
            if (newAccId != null) accountIds.add(newAccId);//add the new and old account id to the set so the re-parenting is handled
        }

        updateCounts(accountIds);
    }

    /**
     * @description       : This method is used to update the total projects count for the accounts.
     * @param accountIds  : Set of account ids
     */
    private static void updateCounts(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) return;

        Map<Id, Integer> countsByAccountId = new Map<Id, Integer>(); //map of account id and project count
        for (AggregateResult ar : [
            SELECT Account__c accountId, COUNT(Id) projectCount
            FROM Project__c
            WHERE Account__c IN :accountIds
            GROUP BY Account__c
        ]) {
            countsByAccountId.put((Id) ar.get('accountId'), (Integer) ar.get('projectCount'));
        }

        List<Account> accountsToUpdate = new List<Account>(); //list of accounts to update
        for (Id accId : accountIds) {
            accountsToUpdate.add(new Account(
                Id = accId,
                Total_Projects__c = countsByAccountId.containsKey(accId) ? countsByAccountId.get(accId) : 0
            ));
        }

        if (!accountsToUpdate.isEmpty()) update accountsToUpdate;
    }
}
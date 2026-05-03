trigger projectTrigger on Project__c (after insert, after update, after delete, after undelete) {
    projectTriggerHandler.run();
}
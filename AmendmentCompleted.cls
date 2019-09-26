/*
*****************************************************************************************************************************************************
Title:      AmendmentCompleted
Purpose:    This Class gets called whenever Amendments are completed.
Revision Log
---------------------------------------------------------------------------------------------------
Sl No.   Date          Author    Modification
---------------------------------------------------------------------------------------------------
1.                               Modified to add Dunning/FMO  Method
2.                               Modified to add The send to SAP Logic for Add/Drop Sites

*****************************************************************************************************************************************************
*/
// added comment from VS test
/*
This Class gets called whenever Amendments are completed.
*/ //Test from VSCode

public class AmendmentCompleted {
    
    public AmendmentCompleted(){
        
    }
    
    /*SNF-269 refactoring here
    Refactor code for new Amendment Flow. SNF-269*/

    public static void completeAddDropAmendment(List<Contract_Amendment__c> contractAmendList) {
        System.debug('contractAmendList ' + contractAmendList);
        Map<String, Contract_Amendment__c> amendmentDetailMap = getContractAmendmentDetailMap(contractAmendList);
        Map<String, List<Contract_Amendment__c>> contractAmendmentMap = getContractAmendmentMap(amendmentDetailMap.values());
        
        List<Contract_Amendment__c> eligibleContractAmendList = getQualifiedForExecutionAmendments(contractAmendList, contractAmendmentMap, amendmentDetailMap);
        List<Contract_Amendment__c> eligibleContractAmendListModified = new List<Contract_Amendment__c>();

        Map<String, List<Contract_Amendment__c>> eligibleContractAmendmentMap = getContractAmendmentMap(eligibleContractAmendList);
        Map<String, List<Amendment_ActionV2__c>> amendActionMap = getAmendActionMap(eligibleContractAmendList); 
        Map<String, List<Deal__c>> contractDealMap = getContractDealMap(eligibleContractAmendmentMap.keySet());
        Map<String, List<CSite__c>> dealCSiteMap  = getDealCSiteMap(contractDealMap.keySet());

        system.debug('#### eligibleContractAmendList.size() = ' + eligibleContractAmendList.size());
        system.debug('#### eligibleContractAmendList BEFORE SORT = ' + eligibleContractAmendList);
        //eligibleContractAmendList.sort();
        system.debug('#### eligibleContractAmendList AFTER SORT = ' + eligibleContractAmendList);

        integer countAmend = 1;
        integer amendindex = 0;
        Contract_Amendment__c nextEligibleAmend;
        
        if (eligibleContractAmendList.size()>0){
             if (eligibleContractAmendList.size() > 1) {
                        nextEligibleAmend = eligibleContractAmendList[1];
             }                        
             eligibleContractAmendListModified.add(eligibleContractAmendList[0]);
        }
        
        system.debug('####eligibleContractAmendListModified ' + eligibleContractAmendListModified);    

        for(Contract_Amendment__c c : eligibleContractAmendListModified){

            List<CSite__c> updatedSiteList = new List<CSite__c>();
            List<CSite__c> addedSiteList = new List<CSite__c>();

            List<Amendment_ActionV2__c> actionList = amendActionMap.get(c.Id);

            for(Amendment_ActionV2__c action : actionList){
                if(action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('Add / Drop') ||
                        action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('Add') ||
                        action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('Drop') ||
                        action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('FMO') ||
                        action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('Dunning') ||
                        action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('Partial Assignment') || // SNF-446 - for partial and full assignment
                        action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('Full Assignment')){
                    
                    if(action.Type__c.equalsIgnoreCase('Add')){
                        List<CSite__c> addedSites = processAmendmentAddAction(action, c.Contract__c, contractDealMap);
                        addedSiteList.addAll(addedSites);

                    } else if(action.Type__c.equalsIgnoreCase('Drop')){
                        if(!action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('Partial Assignment') && !action.Contract_Amendment__r.Amendment_Type__c.equalsIgnoreCase('Full Assignment')){ //SNF-446
                            CSite__c cs =  processAmendmentDropAction(action, c.Contract__c, contractDealMap, dealCSiteMap);
                            if(cs != null){
                                updatedSiteList.add(cs);
                            }
                        }
                    } else if(action.Type__c.equalsIgnoreCase('FMO')){
                        CSite__c cs =  processAmendmentFMOAction(action, c.Contract__c, contractDealMap, dealCSiteMap);
                        
                        if(cs != null){
                            updatedSiteList.add(cs);
                        }
                     } else if(action.Type__c.equalsIgnoreCase('Dunning')){
                        CSite__c cs =  processAmendmentDunningAction(action, c.Contract__c, contractDealMap, dealCSiteMap);
                        
                        if(cs != null){
                            updatedSiteList.add(cs);
                        }
                     }     

                }

            }
            
            system.debug('#### ' + countAmend + ' ### Fired Amendment # ' + c.Amendment_Number__c);
            //System.enqueueJob(new AmendmentPostExecutionFactory(c, updatedSiteList, addedSiteList));



            



            if(!Test.isRunningTest()){
                Mutex__c mutexlock = [SELECT Id,name FROM Mutex__c where name ='Amendment_Lock' limit 1 /*FOR UPDATE*/]; 
                id jobid = QueueableUtil.enqueueJob(new AmendmentPostExecutionFactory(c, updatedSiteList, addedSiteList,mutexLock,nextEligibleAmend));
            }
            countAmend++;
            //QueueableUtil.enqueueJob(new AmendmentPostExecutionFactory(c, updatedSiteList, addedSiteList));
            //QueueableUtil.enqueueJob(new AmendmentDocumentGenerationFactory(c, true));            

        }
        
    }
    
    
    public static void completeCancelAmendmentFlow(List<Contract_Amendment__c> amendment){

        completeAddDropAmendment(amendment);
        
    }   
    
    @Future(callout=true)   
    public static void regenerateDistributeDocuments(Id amendmentId, Boolean notifyUsers){
        
        Contract_Amendment__c amendment = getContractAmendmentById(amendmentId);       
        integer contractVersionNum = (integer)amendment.Contract_Version__c;
        String outputFileName;
        if(amendment.Amendment_Type__c != 'Full Assignment'){ //SNF-446
            if (contractVersionNum == null ){
                system.debug('@@contractVersionNull');
                outputFileName = getCongaOutputFileName(amendment);
            }
            else{
                outputFileName = getCongaOutputFileName(amendment,(integer)amendment.Contract_Version__c);    
            }
        

            //Generate site schedule documents and do not share with contract
            CongaDocumentService conga = new CongaDocumentService(amendment.Contract__c);
            conga.setTemplate('AmendmentNewFlow');
            conga.setTemplateAlias('AmendmentNewFlow');
            conga.setCongaQuery('Amendment_ActionV2_New', amendment.Contract__c); 
            conga.setOutputFileName(outputFileName);
            conga.setDocumentParent(amendment.Id);
    
            String documentId = conga.mergeAndGenerateDocument();
            //ContentDocumentService.shareFileWith(documentId, amendment.Id);
        }
   
    }     

    @TestVisible
    private static Integer getContractVersion(String amendmentId){

        Contract_Amendment__c amendment = [SELECT Id, Contract__r.Contract_Version__c
                                            FROM Contract_Amendment__c 
                                            WHERE Id =: amendmentId];        

        return Integer.valueOf(amendment.Contract__r.Contract_Version__c);
    }     


    @TestVisible
    private static List<Contract_Amendment__c> getQualifiedForExecutionAmendments(List<Contract_Amendment__c> contractAmendList, 
                                                                                    Map<String, List<Contract_Amendment__c>> contractAmendmentMap,
                                                                                    Map<String, Contract_Amendment__c> amendmentDetailMap ){

        List<Contract_Amendment__c> qualifiedContractAmendList = new List<Contract_Amendment__c>();

        for(Contract_Amendment__c currentCA : contractAmendList){

            Contract_Amendment__c currentDetailCA = amendmentDetailMap.get(currentCA.Id);
            List<Contract_Amendment__c> allAmendments = contractAmendmentMap.get(currentDetailCA.Contract__c);

            for(Contract_Amendment__c existingCA : allAmendments){

                if(existingCA.Amendment_Status__c != null && existingCA.Amendment_Status__c.equalsIgnoreCase('Queued') && existingCA.CreatedDate <= currentDetailCA.CreatedDate){
                    qualifiedContractAmendList.add(existingCA);

                } else if(existingCA.Amendment_Status__c != null && existingCA.Amendment_Status__c.equalsIgnoreCase('Pending') && existingCA.CreatedDate <= currentDetailCA.CreatedDate){
                    break;

                } else if(existingCA.Amendment_Status__c != null && existingCA.Amendment_Status__c.equalsIgnoreCase('Queued') && existingCA.CreatedDate >= currentDetailCA.CreatedDate){
                    qualifiedContractAmendList.add(existingCA);

                } else if(existingCA.Amendment_Status__c != null &&  existingCA.Amendment_Status__c.equalsIgnoreCase('Pending') && existingCA.CreatedDate >= currentDetailCA.CreatedDate){
                    break;

                } /*else if(existingCA.Amendment_Status__c != null &&  existingCA.Amendment_Status__c.equalsIgnoreCase('Executed')){
                    break;
                }*/
            }

        }

        return qualifiedContractAmendList;
    }



    @TestVisible
    private static List<CSite__c> processAmendmentAddAction(Amendment_ActionV2__c action, String contractId,
                                Map<String, List<Deal__c>> contractDealMap){

        List<CSite__c> addedSites = new List<CSite__c>();
        List<Deal__c> dealList = contractDealMap.get(contractId);

        for(Deal__c deal : dealList){
            if(deal.commodity__c == action.Site__r.commodity__c){
            CSite__c newSite = new CSite__c();
            newSite.Deal__c = deal.Id;
            newSite.Site__c = action.Site__c;
            newSite.Effective_Start_Date__c = action.Effective_Date__c;
            newSite.Effective_End_Date__c = action.Contract_Amendment__r.Contract__r.Contract_End_Date__c;
            newSite.Billing_Account__c = action.Billing_Account__c;
            newSite.Contract_Amendment_v2__c =action.Contract_Amendment__c;//SNF-269-Defect#34

            addedSites.add(newSite);
            }
        }
        return addedSites;
    }

    @TestVisible
    private static CSite__c processAmendmentDropAction(Amendment_ActionV2__c action, String contractId,
                                Map<String, List<Deal__c>> contractDealMap, Map<String, List<CSite__c>> dealCSiteMap){
        
        List<Deal__c> dealList = contractDealMap.get(contractId);      
        
        for(Deal__c deal : dealList){
            List<CSite__c> cSiteList = dealCSiteMap.get(deal.Id);

            if(cSiteList != null){
                for(CSite__c csite : cSiteList){
                    System.debug('action.Site__c == csite.Site__c ' + action.Site__c + ' *** ' + csite.Site__c);
                    if(action.Site__c == csite.Site__c){
                        csite.Effective_End_Date__c = action.Effective_Date__c;
                        csite.Drop_Reason_Code__c = action.Drop_Reason_Code__c;
                        csite.Dropped_by_Amendment__c = true;
                        csite.Contract_Amendment_v2__c =action.Contract_Amendment__c;//SNF-269-Defect#34

                        System.debug('processAmendmentDropAction csite ' + csite);
                        
                        return csite;
                    }
                }
            }
        }

        return null;
    }  


    @TestVisible
    private static CSite__c processAmendmentFMOAction(Amendment_ActionV2__c action, String contractId,
                                Map<String, List<Deal__c>> contractDealMap, Map<String, List<CSite__c>> dealCSiteMap){
        
        List<Deal__c> dealList = contractDealMap.get(contractId);
        
        for(Deal__c deal : dealList){
            List<CSite__c> cSiteList = dealCSiteMap.get(deal.Id);

            if(cSiteList != null){
                for(CSite__c csite : cSiteList){

                    if(action.Site__c == csite.Site__c){
                        csite.Effective_End_Date__c = action.Effective_Date__c;
                        csite.FMO__c = true;
                        csite.SAP_Integration_Status__c = 'ForceMoveOut request from SAP.';
                        csite.ETC_Override__c = action.ETC_Override__c;
                        csite.Dunning_FMO_By_Amendment__c = true;
                        csite.Dropped_By_Amendment__c = true;
                        csite.SAP_Contract_Number__c = '';  
                        csite.Contract_Amendment_v2__c =action.Contract_Amendment__c;//SNF-269-Defect#34
                        

                        return csite;
                    }
                }
            }
        }

        return null;
    } 


    @TestVisible
    private static CSite__c processAmendmentDunningAction(Amendment_ActionV2__c action, String contractId,
                                Map<String, List<Deal__c>> contractDealMap, Map<String, List<CSite__c>> dealCSiteMap){
        
        List<Deal__c> dealList = contractDealMap.get(contractId);
        
        for(Deal__c deal : dealList){
            List<CSite__c> cSiteList = dealCSiteMap.get(deal.Id);

            if(cSiteList != null){
                for(CSite__c csite : cSiteList){

                    if(action.Site__c == csite.Site__c){
                        csite.Effective_End_Date__c = action.Effective_Date__c;
                        csite.Dunning__c = true;
                        csite.SAP_Integration_Status__c = 'Dunning request from SAP.';
                        csite.Dunning_FMO_By_Amendment__c = true;
                        csite.Dropped_By_Amendment__c = true;
                        csite.SAP_Contract_Number__c = ''; 
                        csite.Contract_Amendment_v2__c =action.Contract_Amendment__c;//SNF-269-Defect#34 
                        

                        return csite;
                    }
                }
            }
        }

        return null;
    }     



    @TestVisible
    private static Map<String, List<Amendment_ActionV2__c>> getAmendActionMap(List<Contract_Amendment__c> contractAmendList){
        Map<String, List<Amendment_ActionV2__c>> amendActionMap = new Map<String, List<Amendment_ActionV2__c>>();

        List<Amendment_ActionV2__c> amendmentActionList = getAmendmentActionByAmendment(contractAmendList);

        for(Amendment_ActionV2__c ac : amendmentActionList){

            if(amendActionMap.containsKey(ac.Contract_Amendment__c)){
                List<Amendment_ActionV2__c> actionList = amendActionMap.get(ac.Contract_Amendment__c);
                actionList.add(ac);
                amendActionMap.put(ac.Contract_Amendment__c, actionList);

            } else {
                List<Amendment_ActionV2__c> actionList = new List<Amendment_ActionV2__c>();
                actionList.add(ac);
                amendActionMap.put(ac.Contract_Amendment__c, actionList);

            }
        }

        return amendActionMap;
    }


    @TestVisible
    private static Map<String, List<Contract_Amendment__c>> getContractAmendmentMap(List<Contract_Amendment__c> contractAmendList){
        Set<Id> contractIdSet = new Set<Id>();
        Map<String, List<Contract_Amendment__c>> contractAmendmentMap = new Map<String, List<Contract_Amendment__c>>();

        //get the unique contract id list of eligible contract amendments 
        for(Contract_Amendment__c ca : contractAmendList){
            if(!contractIdSet.contains(ca.Contract__c)){
                contractIdSet.add(ca.Contract__c);
            }
        }

        //get all contract amendment records belongs to contracts
        List<Contract_Amendment__c> amendmentList = getAllContractAmendmentByContract(contractIdSet);


        for(Contract_Amendment__c ca : amendmentList){
            if(contractAmendmentMap.containsKey(ca.Contract__c)){
                List<Contract_Amendment__c> caList = contractAmendmentMap.get(ca.Contract__c);
                caList.add(ca);
                contractAmendmentMap.put(ca.Contract__c, caList);

            } else {
                List<Contract_Amendment__c> caList = new List<Contract_Amendment__c>();
                caList.add(ca);
                contractAmendmentMap.put(ca.Contract__c, caList);

            }
        }

        return contractAmendmentMap;
    }


    @TestVisible
    private static Map<String, List<Amendment_ActionV2__c>> getAmendActionContractMap(List<Contract_Amendment__c> contractAmendList){
        Map<String, List<Amendment_ActionV2__c>> amendActionContractMap = new Map<String, List<Amendment_ActionV2__c>>();

        List<Amendment_ActionV2__c> amendmentActionList = getAmendmentActionByAmendment(contractAmendList);

        for(Amendment_ActionV2__c ac : amendmentActionList){
            if(amendActionContractMap.containsKey(ac.Contract_Amendment__r.Contract__c)){
                List<Amendment_ActionV2__c> actionList = amendActionContractMap.get(ac.Contract_Amendment__r.Contract__c);
                actionList.add(ac);
                amendActionContractMap.put(ac.Contract_Amendment__r.Contract__c, actionList);

            } else {
                List<Amendment_ActionV2__c> actionList = new List<Amendment_ActionV2__c>();
                actionList.add(ac);
                amendActionContractMap.put(ac.Contract_Amendment__r.Contract__c, actionList);

            }
        }

        return amendActionContractMap;
    }

    @TestVisible
    private static Map<String, List<Deal__c>> getContractDealMap(Set<String> contractIdSet){
        Map<String, List<Deal__c>> contractDealMap = new Map<String, List<Deal__c>>();
        
        List<Deal__c> dealList = getDealListByContract(contractIdSet);

        for(Deal__c dl : dealList){
            if(contractDealMap.containsKey(dl.ContractV2__c)){
                List<Deal__c> deals = contractDealMap.get(dl.ContractV2__c);
                deals.add(dl);
                contractDealMap.put(dl.ContractV2__c, deals);

            } else {
                List<Deal__c> deals = new List<Deal__c>();
                deals.add(dl);
                contractDealMap.put(dl.ContractV2__c, deals);

            }
        }

        return contractDealMap;
    }


    @TestVisible
    private static Map<String, List<CSite__c>> getDealCSiteMap(Set<String> dealIdSet){
        Map<String, List<CSite__c>> dealCSiteMap = new Map<String, List<CSite__c>>();

        List<CSite__c> csitesList = getCsiteList(dealIdSet);

        for(CSite__c cs : csitesList){
            if(dealCSiteMap.containsKey(cs.Deal__c)){
                List<CSite__c> csites = dealCSiteMap.get(cs.Deal__c);
                csites.add(cs);
                dealCSiteMap.put(cs.Deal__c, csites);

            } else {
                List<CSite__c> csites = new List<CSite__c>();
                csites.add(cs);
                dealCSiteMap.put(cs.Deal__c, csites);

            }

        }

        return dealCSiteMap;
    }

    @TestVisible
    private static Map<String, Contract_Amendment__c> getContractAmendmentDetailMap(List<Contract_Amendment__c> amendmentList){
        Map<String, Contract_Amendment__c> amendmentDetailMap = new Map<String, Contract_Amendment__c>();

        List<Contract_Amendment__c> amendmentDetailList = getContractAmendmentDetailList(amendmentList);

        for(Contract_Amendment__c ca : amendmentDetailList){
            if(!amendmentDetailMap.containsKey(ca.Id)){
                amendmentDetailMap.put(ca.Id, ca);

            }
        }

        return amendmentDetailMap;
    }
        

    @TestVisible
    private static Contract_Amendment__c getContractAmendmentById(String amendmentId){
        Contract_Amendment__c amendment = [SELECT Id, CreatedDate,Dunning_FMO_Amendment__c, Opportunity__c,  Credit_Approved__c, Contract__c, 
                                                Contract__r.Contract_End_Date__c,Enmax_Quote__c, Enmax_Quote__r.Product__c, Full_assignment__c, 
                                                Partial_Assignment__c,Returned_from_Customer__c,Sent_to_Billing_System__c, Amendment_Type__c,
                                                Contract__r.Billing_System__c , Account__r.RecordType.Name, Account__r.Id, Name,contract__r.owner.email, //SNF-477
                                                Contract__r.Contract_Start_Date__c,Effective_Start_Date__c,Amendment_Source__c,SAP_Ref_Num__c,
                                                Contract__r.Gas_Product__c,Contract__r.Account__r.Legal_Name__c,Contract__r.Electricity_Product__c,
                                                Contract__r.Contract_Number__c,Amendment_Number__c,Contact__r.Name,Contact__r.FirstName, Contact__r.LastName,
                                                 Account__r.Do_not_generate_amendment_site_schedule__c,Account__r.Do_not_email_site_schedule__c,Contact__r.Email,Contract_Version__c,
                                                 New_Contract__c,assignee_contact__r.email,assignor_contact__r.email // SNF-446
                                            FROM Contract_Amendment__c 
                                            WHERE Id =: amendmentId];

        return amendment;  
    }


    @TestVisible
    private static List<Contract_Amendment__c> getAllContractAmendmentByContract(Set<Id> contractIdSet){
        List<Contract_Amendment__c> amendmentList = [SELECT Id, CreatedDate, Contract__c, Contract__r.Contract_End_Date__c, Amendment_Type__c,
                                                        Amendment_Number__c, Amendment_Status__c, Contract__r.Gas_Product__c,Contract__r.Account__r.Legal_Name__c,
                                                        Contract__r.Electricity_Product__c,Contract__r.Contract_Number__c,Contact__r.Name,Contact__r.FirstName, Contact__r.LastName,
                                                        Account__r.Do_not_generate_amendment_site_schedule__c,Account__r.Do_not_email_site_schedule__c,contract__r.owner.email, //SNF-477
                                                        Contract__r.Billing_System__c,Contract__r.Contract_Status__c,Contact__r.Email,
                                                        New_Contract__c,assignee_contact__r.email,assignor_contact__r.email // SNF-446
                                                    FROM Contract_Amendment__c 
                                                    WHERE Contract__c IN : contractIdSet
                                                    ORDER BY Contract__c, CreatedDate];

        return amendmentList;        

    }


    @TestVisible
    private static List<Contract_Amendment__c> getContractAmendmentDetailList(List<Contract_Amendment__c> contractAmendList){
        List<Contract_Amendment__c> amendmentList = [SELECT Id, CreatedDate, Contract__c, Contract__r.Contract_End_Date__c, Amendment_Type__c,
                                                        Amendment_Number__c, Amendment_Status__c, Contract__r.Gas_Product__c,Contract__r.Account__r.Legal_Name__c,
                                                        Contract__r.Electricity_Product__c,Contract__r.Contract_Number__c,Contact__r.Name,Contact__r.FirstName, Contact__r.LastName,
                                                        Account__r.Do_not_generate_amendment_site_schedule__c,Account__r.Do_not_email_site_schedule__c,contract__r.owner.email, //SNF-477
                                                        Contract__r.Billing_System__c,Contract__r.Contract_Status__c,Contact__r.Email,
                                                        New_Contract__c,assignee_contact__r.email,assignor_contact__r.email // SNF-446
                                                    FROM Contract_Amendment__c 
                                                    WHERE Id IN : contractAmendList];

        return amendmentList;        

    }   


    @TestVisible
    private static List<Amendment_ActionV2__c> getAmendmentActionV2List(String amendment){
         
        List<Amendment_ActionV2__c> amendmentActionList = [SELECT Id, Drop_Reason_Code__c,Site__c, Site__r.Commodity__c, Site__r.Name, 
                                                                    Effective_Date__c, Type__c, Account__c,Contact__c, site__r.Billing_Account__c,ETC_Override__c, 
                                                                    Billing_Account__c 
                                                            FROM Amendment_ActionV2__c 
                                                            WHERE Contract_Amendment__c =: amendment]; 
            
        return amendmentActionList;
            
    }
    
    
    @TestVisible
    private static List<Deal__c> getDealList(Contract_Amendment__c amendment){
    
        List<Deal__c> dealList = [SELECT Id, Commodity__c, Start_Date__c, 
                                        End_Date__c,Product__c,Quote_Term_Price__c 
                                    FROM Deal__c 
                                    WHERE contractV2__c =: amendment.contract__c]; 

        return dealList;
        
    }

    @TestVisible
    private static List<Deal__c> getDealListByContract(Set<String> contractIdSet){
    
        List<Deal__c> dealList = [SELECT Id, Commodity__c, Start_Date__c, ContractV2__c,
                                        End_Date__c,Product__c,Quote_Term_Price__c 
                                    FROM Deal__c 
                                    WHERE contractV2__c IN :contractIdSet]; 

        return dealList;
        
    }    
    
    @TestVisible
    private static List<Csite__c> getCsiteList(List<Deal__c> deals){
        
        List<CSite__c> csitesList = [SELECT Id, Site__c,Drop_Reason_Code__c,Site__r.Commodity__c,
                                                SAP_Contract_Number__c, Dropped_by_Amendment__c, Deal__c, 
                                                Effective_Start_Date__c, Effective_End_Date__c,Billing_Account__c,
                                                Dunning_FMO_By_Amendment__c,ETC_Override__c,SAP_Interaction_Record_Number__c,
                                                SAP_Integration_Status__c 
                                        FROM CSite__c 
                                        WHERE Deal__c in : deals 
                                            AND Dropped_by_Amendment__c != true];
        
        return csitesList;                                  
    }

    @TestVisible
    private static List<Csite__c> getCsiteList(Set<String> deals){
        
        List<CSite__c> csitesList = [SELECT Id, Site__c,Drop_Reason_Code__c,Site__r.Commodity__c,
                                                SAP_Contract_Number__c, Dropped_by_Amendment__c, Deal__c, 
                                                Effective_Start_Date__c, Effective_End_Date__c,Billing_Account__c,
                                                Dunning_FMO_By_Amendment__c,ETC_Override__c,SAP_Interaction_Record_Number__c,
                                                SAP_Integration_Status__c
                                        FROM CSite__c 
                                        WHERE Deal__r.ContractV2__c IN : deals 
                                            AND Dropped_by_Amendment__c != true];
        
        return csitesList;                                  
    }    
    
    @TestVisible
    private static List<Volume_Strip__c> getVolumeStripList(List<Deal__c> deals){
        
        List<Volume_Strip__c> siteVolumesList = [SELECT Id, CSite__r.Site__c, January__c, February__c, March__c, 
                                                        April__c, May__c, June__c, July__c, August__c, September__c, October__c, 
                                                        November__c, December__c, total__c, Status__c, Effective_Start_Date__c, 
                                                        Effective_End_Date__c, Block_Volume__c,Type__c,deal__c //SAL-2317 Added deal__c
                                                FROM Volume_Strip__c 
                                                WHERE Deal__c IN : deals 
                                                    AND (Status__c = 'Active' OR Status__c = 'Future')];
                                                    
        return siteVolumesList;                                           
    }
    
    @TestVisible
    private static List<Volume_Strip__c> getSiteVolumeList(List<Csite__c> cSites){
        
        List<Volume_Strip__c> siteVolumesList = [SELECT Id, CSite__r.Site__c, January__c, February__c, March__c, April__c, May__c, 
                                                        June__c, July__c, August__c, September__c, October__c, November__c, December__c, 
                                                        total__c, Status__c, Effective_Start_Date__c, Effective_End_Date__c, Block_Volume__c 
                                                    FROM Volume_Strip__c 
                                                    WHERE CSite__c in : cSites 
                                                        AND (Status__c = 'Active' OR Status__c = 'Future')];

        return siteVolumesList;                                            
    }
    
    @TestVisible
    private static List<Quote_Term_Price__c> getQTPList(Contract_Amendment__c amendment){
    
        List<Quote_Term_Price__c> qtpList = [SELECT Load_Shape__c, Retail_Price__c, Transfer_Price__c, Term__c, Commodity__c, 
                                                    Start_Date__c, End_Date__c, January__c, February__c, March__c, April__c, May__c, 
                                                    June__c,July__c, August__c,September__c, October__c, November__c, December__c 
                                                FROM Quote_Term_Price__c 
                                                WHERE Enmax_Quote__c =: amendment.Enmax_Quote__c 
                                                        AND Selected__c = true];
                                                    
        return qtpList;
        
    } 
    
    @TestVisible
    private static List<CPrice__c> getCpriceList(List<Deal__c> deals){
    
        List<CPrice__c> activeCPriceList = [SELECT Id, Deal__c, Product__c, Load_Shape__c, Retail_Price__c, Transfer_Price__c,Volume_Strip__c, //SAL-2317 Added Volume_Strip__c 
                                                    Term__c,  Effective_End_Date__c, Effective_Start_Date__c, Admin_Fee_Unused__c,
                                                    Admin_Fee_Excess__c,Admin_fee__c, Retail_margin__c, Energy_Price__c, Transaction_Fee__c 
                                            FROM CPrice__c 
                                            WHERE Deal__c in : deals 
                                                AND (Status__c = 'Active' OR Status__c = 'Future')];
    
        return activeCPriceList;
    
    }
    
    @TestVisible
    private static ContractV2__c getContract(Contract_Amendment__c amendment){
    
        ContractV2__c contract = [SELECT id, Name, Contract_name__c, Contract_Number__c, Contract_Start_Date__c, Contract_End_Date__c, 
                                        X30_Day_Out_Clause__c, Account_Legal_Name__c, blended__c, Commodity__c, Number_of_Amendments__c, 
                                        Version_Override__c,Effective_Date__c, Electricity_Product__c, Emergency_Contact__c, Document_ID__c, 
                                        contract_id__c, Legal_Entity__c, Max_Threshold__c, Min_Threshold__c, Retailer_Id__c,Evergreen_Price_MWh__c, 
                                        Gas_Product__c, Opportunity__c, Opportunity__r.e_verified_volume__c, Opportunity__r.g_verified_volume__c, 
                                        Opportunity__r.E_Product__c, Primary_Contact__c, Rate_Plan__c, Rec__c, REC_Price__c,
                                        Signing_Authority__c, Small_Comm__c, UFE_LL_TC_Handling__c, Business_Segment__c, contract_type__c, 
                                        DOA__c, DOA__r.Name, DOA__r.Title, Billing_System__c,Amendment_Effective_Date_Override__c, 
                                        Previous_Amendment_Completion_Date__c, Amendment_Created_Date__c,
                                        Related_DOA__c, // SAL-1853
                                        Account__r.id 
                                    FROM ContractV2__c 
                                    WHERE Id =: amendment.contract__c];
     
        return contract;
    }  
    
    @TestVisible
    private static Id getContractId(string amendmentId){
        
        ContractV2__c contractId  = [Select Id from ContractV2__c where Id =:amendmentId];
        return contractId.Id;
    }

    @TestVisible
    private static List<Amendment_ActionV2__c> getAmendmentActionByAmendment(List<Contract_Amendment__c> contractAmendList){
         
        List<Amendment_ActionV2__c> amendmentActionList = [SELECT Id, Drop_Reason_Code__c,Site__c, site__r.Commodity__c, Effective_Date__c, 
                                                                    Type__c, Account__c,Contact__c, site__r.Billing_Account__c,ETC_Override__c, 
                                                                    Billing_Account__c, Contract_Amendment__r.Contract__c, Contract_Amendment__c,
                                                                    Contract_Amendment__r.Amendment_Type__c,Contract_Amendment__r.Contract__r.Contract_End_Date__c
                                                                    
                                                            FROM Amendment_ActionV2__c 
                                                            WHERE Contract_Amendment__c IN :contractAmendList]; 
            
        return amendmentActionList;
            
    }


    @TestVisible
    private static List<CSite__c> processDropSites(List<CSite__c> cSiteList, List<Amendment_ActionV2__c> amendmentList, String dropType){
        List<CSite__c> updatedSites = new List<CSite__c>();

        for(Amendment_ActionV2__c action : amendmentList){

            for(CSite__c csite : cSiteList){

                if(action.Site__c == csite.Site__c){
                    csite.Effective_End_Date__c = action.Effective_Date__c;
                    csite.Drop_Reason_Code__c = action.Drop_Reason_Code__c;
                    
                    if(dropType.equalsIgnoreCase('Amendment')){
                        csite.Dropped_by_Amendment__c = true;
                    }

                    updatedSites.add(csite);
                }
            }

        }

        return updatedSites;
    }

    //PROCESS PARTIAL ASSIGNMENT
    
    @TestVisible
    private static List<CSite__c> processDropSite(List<CSite__c> cSiteList, Amendment_ActionV2__c action, String dropType){
        List<CSite__c> updatedSites = new List<CSite__c>();

        for(CSite__c csite : cSiteList){

            if(action.Site__c == csite.Site__c){
                csite.Effective_End_Date__c = action.Effective_Date__c;
                csite.Drop_Reason_Code__c = action.Drop_Reason_Code__c;
                
                if(dropType.equalsIgnoreCase('Amendment')){
                    csite.Dropped_by_Amendment__c = true;
                }

                updatedSites.add(csite);
            }
        }

        return updatedSites;
    }    

    @TestVisible
    private static List<CSite__c> processAddSites(List<Deal__c> dealList, List<Amendment_ActionV2__c> amendmentList, Contract_Amendment__c amendment, String businessSegment){
        List<CSite__c> addedSites = new List<CSite__c>();

        for(Amendment_ActionV2__c action : amendmentList){

            for(Deal__c deal : dealList){

                CSite__c newSite = new CSite__c();
                newSite.Deal__c = deal.Id;
                newSite.Site__c = action.Site__c;
                newSite.Effective_Start_Date__c = action.Effective_Date__c;
                newSite.Effective_End_Date__c = amendment.Contract__r.Contract_End_Date__c;
                newSite.Original_End_Date__c = amendment.Contract__r.Contract_End_Date__c;
                newSite.SAP_Interaction_Record_Number__c = amendment.SAP_Ref_Num__c;

                if(businessSegment.equalsIgnoreCase('Commercial Accounts')){
                    newSite.Billing_Account__c = action.Billing_Account__c;

                } else {
                    newSite.Billing_Account__c = action.Site__r.Billing_Account__c;

                }

                addedSites.add(newSite);
            }
        }

        return addedSites;
    }  


    @TestVisible
    private static CSite__c processAddSite(Deal__c deal, Amendment_ActionV2__c action, Contract_Amendment__c amendment, String businessSegment){

        CSite__c addedSite = new CSite__c();
        addedSite.Deal__c = deal.Id;
        addedSite.Site__c = action.Site__c;
        addedSite.Effective_Start_Date__c = system.today();
        addedSite.Effective_End_Date__c = amendment.Contract__r.Contract_End_Date__c;
        addedSite.Original_End_Date__c = amendment.Contract__r.Contract_End_Date__c;

        addedSite.SAP_Interaction_Record_Number__c = amendment.SAP_Ref_Num__c;

        if(businessSegment.equalsIgnoreCase('Commercial Accounts')){
            addedSite.Billing_Account__c = action.Billing_Account__c;

        } else {
            addedSite.Billing_Account__c = action.Site__r.Billing_Account__c;

        }

        return addedSite;
    }    



    @TestVisible
    private static List<Volume_Strip__c> processVolumeStrips(List<CSite__c> cSiteList, String type){
        List<Volume_Strip__c> vStripList = new List<Volume_Strip__c>();

        for(CSite__c cSite : cSiteList){
            Volume_Strip__c vStrip = new Volume_Strip__c(
                    January__c = 0, 
                    February__c = 0, 
                    March__c = 0, 
                    April__c = 0, 
                    May__c = 0,
                    June__c = 0, 
                    July__c = 0, 
                    August__c = 0, 
                    September__c = 0, 
                    October__c = 0,
                    November__c = 0, 
                    December__c = 0, 
                    Type__c = type,
                    Effective_Start_Date__c = cSite.Effective_Start_Date__c, 
                    Effective_End_Date__c = cSite.Effective_End_Date__c, 
                    CSite__c = cSite.id,
                    Deal__c = cSite.Deal__c

            );

            vStripList.add(vStrip);
        }

        return vStripList;
    } 


    @TestVisible
    private static List<Volume_Strip__c> processVolumeStrips(List<CSite__c> cSiteList, Contract_Amendment__c amendment, String type){
        List<Volume_Strip__c> vStripList = new List<Volume_Strip__c>();

        for(CSite__c cSite : cSiteList){
            Volume_Strip__c vStrip = new Volume_Strip__c(
                    January__c = 0, 
                    February__c = 0, 
                    March__c = 0, 
                    April__c = 0, 
                    May__c = 0,
                    June__c = 0, 
                    July__c = 0, 
                    August__c = 0, 
                    September__c = 0, 
                    October__c = 0,
                    November__c = 0, 
                    December__c = 0, 
                    Type__c = type,
                    Effective_Start_Date__c = cSite.Effective_Start_Date__c, 
                    Effective_End_Date__c = amendment.Contract__r.Contract_End_Date__c, 
                    CSite__c = cSite.id,
                    Deal__c = cSite.Deal__c

            );

            vStripList.add(vStrip);
        }

        return vStripList;
    } 

    @TestVisible
    private static void lockAmendment(Contract_Amendment__c amendment){

        Approval.lock(amendment,false);

    }   


    public static void generateShareDistributeDocuments(Contract_Amendment__c amendment, Boolean notifyUsers){
        
        boolean notifyUser = notifyUsers;
        
        if(amendment.Account__r.Do_not_email_site_schedule__c){
            
           notifyUser = false;
        }
        system.debug('@@EmailSite@@' +amendment.account__r.Do_not_email_site_schedule__c);
        system.debug('@@Amendment@@'+amendment);
    
        //AmendmentPostExecutionFactory postExec = new AmendmentPostExecutionFactory(amendment, notifyUser);
        //System.enqueueJob(postExec);    
    
        /*
        Contract_Amendment__c amendment = getContractAmendmentById(amendmentId);//Future calls does support only primary data types as input patameters
        Id conId = getContractId(contractId);
        String outputFileName = getCongaOutputFileName(amendment);

        //Generate site schedule documents and shared with contract
        //CongaDocumentService conga = new CongaDocumentService(amendment.Id);
        CongaDocumentService conga = new CongaDocumentService(conId);
        conga.setTemplate('AmendmentNewFlow');
        conga.setTemplateAlias('AmendmentNewFlow');
        conga.setCongaQuery('Amendment_ActionV2_New', conId); 
        conga.setOutputFileName(outputFileName);

        String documentId = conga.mergeAndGenerateDocument();

        ContentDocumentService.shareFileWith(documentId, amendment.Id); 

        if(notifyUsers){
            //Email generated PDF
            notifyUsers(documentId, amendment);                
        }
        */
   
    } 
    
    

    //replicate the same logic as in Contract__c.Conga_Generated_Document_Name__c for the amendments
    
    @TestVisible
    private static String getCongaOutputFileName(Contract_Amendment__c amendment){
        String fileName = '';
        String elecProduct = amendment.Contract__r.Electricity_Product__c != null ? amendment.Contract__r.Electricity_Product__c : '';
        String gasProduct = amendment.Contract__r.Gas_Product__c != null ? amendment.Contract__r.Gas_Product__c : '';
        Integer versionNum = getContractVersion(amendment.Id);
        String version = versionNum != null ? String.valueOf(versionNum) : ''; 
        system.debug('@@amendment.Amendment_Type__c=='+amendment.Amendment_Type__c);
        if(amendment.Amendment_Type__c == 'Partial Assignment' && amendment.Amendment_Type__c != 'Full Assignment'){ // SNF-446
            
            fileName = amendment.Amendment_Type__c == 'Partial Assignment' ? 'PA-':(amendment.Amendment_Type__c == 'Full Assignment' ? 'FA-' : amendment.Amendment_Type__c) + '-';
            system.debug('@@fileName=='+fileName);
            fileName = fileName + amendment.Contract__r.Contract_Number__c;
            fileName = fileName + '.V';
            fileName = fileName + amendment.Contract_Version__c;//amendment.Amendment_Number__c;
            fileName = fileName + '-';
            fileName = fileName + amendment.Contract__r.Account__r.Legal_Name__c.replaceAll('[^a-zA-Z0-9\\s+]', '');
            fileName = fileName + '-';
            fileName = fileName + elecProduct;
            fileName = fileName + '-';   
            fileName = fileName + gasProduct;
        
        } else if(amendment.Amendment_Type__c != 'Partial Assignment' || amendment.Amendment_Type__c != 'Full Assignment'){ // SNF-446
            system.debug('inside else');
            fileName = amendment.Contract__r.Contract_Number__c;
            fileName = fileName + '.V';
            fileName = fileName + version;
            fileName = fileName + '-';
            fileName = fileName + amendment.Contract__r.Account__r.Legal_Name__c.replaceAll('[^a-zA-Z0-9\\s+]', '');
            fileName = fileName + '-';
            fileName = fileName + elecProduct;
            fileName = fileName + '-';   
            fileName = fileName + gasProduct;
        }

        if(fileName.length() > 75){
            fileName = fileName.substring(0, 75);
        }

        //Replace all spaces in file name with + sign
        //https://support.getconga.com/Conga_Composer/Customizing_Composer_with_Parameters/Composer_Parameter_Guide/OFN

        fileName = fileName.replace(' ', '+');

        return fileName;
    } 
     @TestVisible
    public static String getCongaOutputFileName(Contract_Amendment__c amendment,integer contractVersionNum){
        
        String fileName = '';
        String elecProduct = amendment.Contract__r.Electricity_Product__c != null ? amendment.Contract__r.Electricity_Product__c : '';
        String gasProduct = amendment.Contract__r.Gas_Product__c != null ? amendment.Contract__r.Gas_Product__c : '';
        
        //Integer versionNum = getContractVersion(amendment.Id);
        Integer versionNum = contractVersionNum;
        String version = versionNum != null ? String.valueOf(versionNum) : '';        
        
        
        if(amendment.Amendment_Type__c == 'Partial Assignment' || amendment.Amendment_Type__c == 'Full Assignment'){ // SNF-446
            
            fileName = amendment.Amendment_Type__c == 'Partial Assignment' ? 'PA-':(amendment.Amendment_Type__c == 'Full Assignment' ? 'FA-' : amendment.Amendment_Type__c) + '-';
            system.debug('@@fileName=='+fileName);
            fileName = fileName + amendment.Contract__r.Contract_Number__c;
            fileName = fileName + '.V';
            fileName = fileName + amendment.Contract_Version__c;//amendment.Amendment_Number__c;
            fileName = fileName + '-';
            fileName = fileName + amendment.Contract__r.Account__r.Legal_Name__c.replaceAll('[^a-zA-Z0-9\\s+]', '');
            fileName = fileName + '-';
            fileName = fileName + elecProduct;
            fileName = fileName + '-';   
            fileName = fileName + gasProduct;
        
        } else{
        
            fileName = amendment.Contract__r.Contract_Number__c;
            fileName = fileName + '.V';
            fileName = fileName + version;
            fileName = fileName + '-';
            fileName = fileName + amendment.Contract__r.Account__r.Legal_Name__c.replaceAll('[^a-zA-Z0-9\\s+]', '');    //Conga does not support special chanracters in file name including "&"
            fileName = fileName + '-';
            fileName = fileName + elecProduct;
            fileName = fileName + '-';   
            fileName = fileName + gasProduct;
        }
        if(fileName.length() > 75){
            fileName = fileName.substring(0, 75);
        }

        //Replace all spaces in file name with + sign
        //https://support.getconga.com/Conga_Composer/Customizing_Composer_with_Parameters/Composer_Parameter_Guide/OFN

        fileName = fileName.replace(' ', '+');

        return fileName;
    } 

    @TestVisible
    private static void notifyUsers(String documentId, Contract_Amendment__c amendment){
        String emailBody = '';

        ContentVersion docu = ContentDocumentService.getDocumentContentById(documentId);

        if(amendment.Amendment_Type__c.equalsIgnoreCase('Add / Drop') ||
            amendment.Amendment_Type__c.equalsIgnoreCase('Drop') ||
            amendment.Amendment_Type__c.equalsIgnoreCase('Add') ){
            
            emailBody = getAddDropEmailBody(amendment);

        } else {
            emailBody = getAddDropEmailBody(amendment);

        }

        composeAndSendEmail('Add Drop Site Schedule', emailBody, docu, amendment);
    }

    @TestVisible
    private static String getAddDropEmailBody(Contract_Amendment__c amendment){
        String emailBody = '';

        emailBody = '<p style="font-family:Calibri">';      //Make sure we have the correct font type and size for emails
        emailBody = emailBody + 'Dear ' + amendment.Contact__r.Name + ',';
        emailBody = emailBody + '<br/><br/>';
        emailBody = emailBody + 'Here is the amendment to add/remove site(s) ' 
                                + getCommaSeparatedSites(amendment) 
                                + ' to/from ' 
                                + amendment.Contract__r.Contract_Number__c + '. '
                                + 'Please keep this copy for your reference.';
        emailBody = emailBody + '<br/><br/>';
        emailBody = emailBody + 'Please note, site(s) will be enrolled/de-enrolled within 3 business days.';
        emailBody = emailBody + '<br/><br/>';
        emailBody = emailBody + 'Kind regards,';
        emailBody = emailBody + '<br/><br/>';
        emailBody = emailBody + 'Client Care Team, Commercial Markets, Enmax Energy';
        emailBody = emailBody + '</p>';

        return emailBody;
    }

    @TestVisible
    private static Email_Notifications__c getEmailNotification(String templateName){

        Email_Notifications__c notification = Email_Notifications__c.getValues(templateName);
        return notification;

    }  


    @TestVisible
    private static void composeAndSendEmail(String notificationName, String emailBody, ContentVersion docu, Contract_Amendment__c amendment){

        Messaging.reserveSingleEmailCapacity(1);

        Email_Notifications__c notification = getEmailNotification(notificationName);
        Messaging.EmailFileAttachment attach = getAttachment(docu);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        String[] toAddresses = notification.To_Address__c.split(',');
        String[] ccAddresses = notification.CC_Address__c.split(',');
        
        mail.setToAddresses(toAddresses);
        mail.setCcAddresses(ccAddresses);
        mail.setBccSender(false);
        mail.setSubject(notification.Subject__c);
        mail.setPlainTextBody(emailBody.stripHtmlTags());
        mail.setHtmlBody(emailBody);
        mail.setWhatId(amendment.Id);
        mail.setSaveAsActivity(true);        
        
        //set the attachment if it generated
        if(attach != null){
            mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attach });
        }

        if(!Test.isRunningTest()){
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        }      

    }


    @TestVisible
    private static Messaging.EmailFileAttachment getAttachment(ContentVersion docu){
        Messaging.EmailFileAttachment fileAttachment = new Messaging.EmailFileAttachment();
        fileAttachment.setContentType('application/pdf');
        fileAttachment.setInline(false);
        fileAttachment.setFileName(docu.PathOnClient);
        fileAttachment.setBody(docu.VersionData);

        return fileAttachment;
    }  

    @TestVisible
    private static String getCommaSeparatedSites(Contract_Amendment__c amendment) {
        List<String> siteList = new List<String>();

        List<Amendment_ActionV2__c> actionList = getAmendmentActionV2List(amendment.Id);

        for(Amendment_ActionV2__c action :actionList){
           if(action.Type__c.equalsIgnoreCase('Add') || action.Type__c.equalsIgnoreCase('Drop')){
               siteList.add(action.Site__r.Name);
           }
        } 
        
    return String.join(siteList, ',');    
        
    }                     

    @TestVisible
    private static List<Contract_Amendment__c> getNoDocumentAccountList(List<Contract_Amendment__c> amendmentList){
        
        
        List<Contract_Amendment__c> amendmentAccountList = new List<Contract_Amendment__c>([Select Account__r.Id from Contract_Amendment__c where Id =: amendmentList AND 
                                                                                            Account__r.Do_not_generate_amendment_site_schedule__c = false]);
                                                        
       return amendmentAccountList;
        
        
        
    }


    /*SNF-269 code refactoring end here */
















     public static void completeAmendment(list<Id> amendmentId) {

        Contract_Amendment__c amendment = getContractAmendmentById(amendmentId[0]);

        amendment.Effective_Start_Date__c = system.today();
        
        list<Amendment_ActionV2__c> amendmentActionList = getAmendmentActionV2List(amendment.Id);

        for(Amendment_ActionV2__c action : amendmentActionList){
            if(action.Type__c == 'Dunning'|| action.Type__c == 'FMO'){
              completeAmendmentForDunningAndFMO(amendment); 
            }
            else if(action.Type__c == 'Full Assignment' || action.Type__c == 'Partial Assignment'){
              completeAmendmentForAssignment(amendment); 
            }
        }
        
    }      
        
        public static void completeAmendmentForAssignment(Contract_Amendment__c amendment){
        
        list<cSite__c> newSites = new list<cSite__c>();
        List<Volume_Strip__c> newVolumeStrip = new List<Volume_Strip__c>();
        list<cSite__c> updateSites = new list<cSite__c>();
        list<cPrice__c> newPrices = new list<cPrice__c>();
        list<Quote_Term_Price__c> qtps = new list<Quote_Term_Price__c>();
        String Commodity = '';
                
        list<Amendment_ActionV2__c> actions = getAmendmentActionV2List(amendment.Id);
        list<Deal__c> deals = getDealList(amendment);
        list<cSite__c> cSites = getCsiteList(deals);
        list<cPrice__c> activeCPrices = getCpriceList(deals);
        list<Volume_Strip__c> volumeStrips = getVolumeStripList(deals);
        list<Volume_Strip__c> siteVolumes = getSiteVolumeList (cSites);
        ContractV2__c contract = getContract(amendment);
                             
           
            
                             
        if(amendment.Full_Assignment__c || amendment.Partial_Assignment__c){   
            Amendment_ActionV2__c assignmentAction = new Amendment_ActionV2__c(); 
                
                for(Amendment_ActionV2__c action : actions){
                    if(action.Type__c == 'Full Assignment' || action.Type__c == 'Partial Assignment')
                    {
                        assignmentAction = action;
                    }
                }
                
            ContractV2__c newContract = new ContractV2__c(amendment__c = true);
            
            AssignmentContractCreation_V2 create = new AssignmentContractCreation_V2();
            Map<id,id> oldAndCurrentId = new Map<id,id>();  //SAL-2317
            
            if(amendment.Full_Assignment__c){
                newContract = create.FullAssignment(contract, amendment, assignmentAction);
                id newBillingAccountId =  newBillingAccount(contract.Account__r.id);//SAL-1830
                list<Deal__c> newDeals = new list<Deal__c>();
                for(Deal__c deal : deals){
                    Deal__c newDeal = deal.clone(false, true);
                    newDeal.ContractV2__c = newContract.Id;
                    newDeal.Commodity__c = deal.Commodity__c;
                    insert newDeal;
               
                    for (cSite__c cSite : cSites){
                        if(cSite.Deal__c == deal.Id){
                            cSite__c newCSite = cSite.clone(false, true);
                            newCSite.Deal__c = newDeal.Id;
                            newCSite.Billing_Account__c =newBillingAccountId;    //SAL-1830
                            newSites.add(newCSite);
                        }
                    }
                 
                //SAL-2317 start 
                        
                // for(cPrice__c cPrice : activeCPrices){
                //     if(cPrice.Deal__c == deal.Id){
                //         cPrice__c newCPrice = cPrice.clone(false, true);
                //         newCPrice.deal__c = newDeal.Id;
                //         newPrices.add(newCPrice);
                //     }
                // }
                
                // for(Volume_Strip__c volume : volumeStrips){
                //     Volume_Strip__c newVolume = volume.clone(false, true);
                //     newVolume.deal__c = newDeal.Id;
                //     newVolumeStrip.add(newVolume);
                //     oldAndCurrentId.put(volume.id,newVolume.id);
                // }
                
                System.debug(' deal.id = ' + deal.id);
                System.debug('volumeStrips = ' + volumeStrips);
                for(Volume_Strip__c volume : volumeStrips){
                    System.debug('volume.deal__c = ' + volume.deal__c + ' deal.id = ' + deal.id);
                    if(volume.deal__c == deal.id){
                        System.debug('volume.deal__c = ' + volume.deal__c + ' deal.id = ' + deal.id);
                        Volume_Strip__c newVolume = volume.clone(false, true);
                        newVolume.deal__c = newDeal.Id;
                        newVolumeStrip.add(newVolume);
                        System.debug('Under volume');
                    }
                }
                
                for(cPrice__c cPrice : activeCPrices){
                    if(cPrice.Deal__c == deal.Id){
                        cPrice__c newCPrice = cPrice.clone(false, true);
                        newCPrice.deal__c = newDeal.Id;
                        newCPrice.volume_strip__c = cPrice.volume_Strip__c;
                                
                        System.debug(oldAndCurrentId);
                                
                                
                        newPrices.add(newCPrice);
                    }
                            
                }
                
            }
            insert newSites;
            insert newVolumeStrip;
                    
            //SAL-2317 Start
                    
            Integer count = 0;
                    
            for(Volume_Strip__c volume : volumeStrips){
                oldAndCurrentId.put(volume.id,newVolumeStrip[count++].id);
            }
            for(cPrice__c cPrice : newPrices){
                if(oldAndCurrentId.containsKey(cPrice.volume_Strip__c)){
                    cPrice.volume_strip__c = oldAndCurrentId.get(cPrice.volume_Strip__c);
                    System.debug('oldAndCurrentId.get(cPrice.volume_Strip__c);' + oldAndCurrentId.get(cPrice.volume_Strip__c));
                }
            }
                    
            insert newPrices;
                    
                    
                    
            //SAL-2317 End
                    
                    list<Volume_Strip__c> newSiteVolumeStrip = new list<Volume_Strip__c>();
                    for(cSite__c cSite : newSites){
                        for(Volume_Strip__c vStrip : siteVolumes){
                            if(cSite.site__c == vStrip.CSite__r.Site__c){
                                Volume_Strip__c newVolume = vStrip.clone(false, true);      
                                newVolume.CSite__c = cSite.id;
                                newSiteVolumeStrip.add(newVolume);
                                System.debug('AmendmentCompleted - Adding a New Volume Strip for Site Volumes - newVolume = ' + newVolume);
                            }    
                        }
                    }
                    System.debug('AmendmentCompleted - Inserting Volumes - newSiteVolumeStrip = ' + newSiteVolumeStrip);
                    insert newSiteVolumeStrip;
                    
            }
            else
                {
                    newContract = create.PartialAssignment(contract, amendment, assignmentAction);
                    id newBillingAccountId =  newBillingAccount(contract.Account__r.id);    //SAL-1830
                    system.debug(activeCPrices);
                    
                    //list<Deal__c> newDeals = new list<Deal__c>();
                    list<Id> partialSites = new list<Id>();
                    for(Deal__c deal : deals){
                        Deal__c newDeal = new Deal__c(ContractV2__c = newContract.Id, Commodity__c = deal.commodity__c);
                        newDeal.ContractV2__c = newContract.Id;
                        newDeal.Commodity__c = deal.Commodity__c;
                        insert newDeal;
                        
                        for(Amendment_ActionV2__c action : actions){
                          if(action.site__r.Commodity__c == deal.commodity__c){
                                processDropSites(cSites,actions,'Drop');
                            }
                        
                        }
                    
                        for(cPrice__c cPrice : activeCPrices){
                            if(cPrice.Deal__c == deal.Id){
                                cPrice__c newCPrice = cPrice.clone(false, true);
                                newCPrice.deal__c = newDeal.Id;
                                newPrices.add(newCPrice);
                            }
                        }
                        
                    if(contract.Business_Segment__c != 'Commercial Accounts'){
                       
                      //processVolumeStrips(cSites, amendment, 'Historical');
                        Volume_Strip__c newVolume = new Volume_Strip__c(January__c = 0, February__c = 0, March__c = 0, April__c = 0, May__c = 0, June__c = 0, July__c = 0, August__c = 0, September__c = 0, October__c = 0, November__c = 0, December__c = 0);
                        newVolume.deal__c = newDeal.Id;
                        newVolume.Effective_Start_Date__c = volumeStrips[0].Effective_Start_Date__c;
                        newVolume.Effective_End_Date__c = volumeStrips[0].Effective_End_Date__c;
                        
                        for(Volume_Strip__c historicalVolumes : [SELECT Id, January__c, February__c, March__c, April__c, May__c, June__c, July__c, August__c, September__c, October__c, November__c, December__c, Total__c FROM Volume_Strip__c WHERE Site__c in : partialSites AND type__c = 'SAS' AND (Status__c = 'Active' OR Status__c = 'Future')])
                            {
                                historicalVolumes(newVolume,historicalVolumes);    
                            }
                            
                        newVolumeStrip.add(newVolume);
                    }
                    else
                    {
                        nonHistoricalVolumes(newVolumeStrip,volumeStrips,newDeal);
                        //processVolumeStrips(cSites, amendment, 'Contract');
                    }
            } 
                    insert newSites;
                    insert newPrices;
                    insert newVolumeStrip;
                    update updateSites;    
                        
                list<Id> siteIds = new list<Id>();
                for(cSite__c site : newSites){
                    siteIds.add(site.Site__r.Id);
                }
                //list<Volume_Strip__c> newSiteVolumeStrip = new list<Volume_Strip__c>();
                processVolumeStrips(newSites, amendment, 'Historical');
                
                // for(cSite__c cSite : newSites){
                //     for(Volume_Strip__c vStrip : siteVolumes){
                //         if(cSite.site__c == vStrip.CSite__r.Site__c){
                //             Volume_Strip__c newVolume = vStrip.clone(false, true);      
                //             newVolume.CSite__c = cSite.id;
                //             newVolume.Type__c = 'Historical';
                //             newSiteVolumeStrip.add(newVolume);
                                    
                //         }    
                //     }
                // }
                    
                // System.debug('AmendmentCompleted - Inserting Volumes - newSiteVolumeStrip = ' + newSiteVolumeStrip);
                // insert newSiteVolumeStrip;    
                        
        }
                if(!newSites.isEmpty())
                {
                    //insert newSites;
                }

        } 
     }

                              
    
    //SAL-1830 Start
    public static id newBillingAccount(id AccountId){
        
        Account acc = [SELECT House_No__c,PO_Box__c, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, BillingLatitude, BillingLongitude,Unit__c FROM Account WHERE id =: AccountId ];
        
        Billing_Account__c newBillingAccount = new Billing_Account__c();
        newBillingAccount.Account__c = acc.id;
        newBillingAccount.City__c = acc.BillingCity;
        newBillingAccount.Country__c = acc.BillingCountry;
        newBillingAccount.Region__c = acc.BillingState;
        newBillingAccount.Postal_Code__c = acc.BillingPostalCode;
        newBillingAccount.Street__c = acc.BillingStreet;
        newBillingAccount.House_No__c = acc.House_No__c;
        newBillingAccount.Interest_Key__c = 'E2';
        newBillingAccount.PO_Box__c = acc.PO_Box__c;
        newBillingAccount.Unit__c = acc.Unit__c; // added for populating Unit - by Sonali
        
        insert newBillingAccount;
        
        return newBillingAccount.id;
    }
    //SAL-1830 End
    
    //@Future
    // public static void completeFMODunningAmendment(String amendmentId) {
        
    //     Contract_Amendment__c amendment = getContractAmendmentById(amendmentId);

    //     //Checking the type here for FMO and Dunning
    //     if(amendment.Amendment_Type__c == 'FMO' || amendment.Amendment_Type__c == 'Dunning' ){
    //         completeAmendmentForDunningAndFMO(amendment); 
    //     }
        
        
    // }
    
    //Method to hundle Dunning and FMO actions
    public static void completeAmendmentForDunningAndFMO(Contract_Amendment__c amendment){
    try{
        
        
        list<cSite__c> newSites = new list<cSite__c>();
        list<Volume_Strip__c> newVolumeStrip = new list<Volume_Strip__c>();
        list<cSite__c> updateSites = new list<cSite__c>();
        list<cPrice__c> newPrices = new list<cPrice__c>();
        list<Amendment_ActionV2__c> actions = getAmendmentActionV2List(amendment.Id);
        list<Deal__c> deals = getDealList(amendment);
        list<cSite__c> cSites = getCsiteList(deals);
        list<Volume_Strip__c> siteVolumes = getSiteVolumeList(cSites);
        Contract_Amendment__c ca=[select id,sap_ref_num__c from Contract_Amendment__c  where id= : amendment.id];
        list<Quote_Term_Price__c> qtps = getQTPList(amendment);
        list<cPrice__c> activeCPrices = getCpriceList(deals);
        list<Volume_Strip__c> volumeStrips = getVolumeStripList(deals);
        //SAL-435
        ContractV2__c contract = getContract(amendment);
                         
                         
        if(amendment.Full_Assignment__c || amendment.Partial_Assignment__c)
        {   
            Amendment_ActionV2__C assignmentAction = new Amendment_ActionV2__c(); 
            for(Amendment_ActionV2__c action : actions)
            {
                if(action.Type__c == 'Full Assignment' || action.Type__c == 'Partial Assignment')
                {
                    assignmentAction = action;
                }
            }
            ContractV2__c newContract = new ContractV2__c(amendment__c = true);
            AssignmentContractCreation_V2 create = new AssignmentContractCreation_V2();
            List<Volume_Strip__c> tempVolumeStripList = new List<Volume_Strip__c>(); //SAL-2317
            if(amendment.Full_Assignment__c)
            {
                newContract = create.FullAssignment(contract, amendment, assignmentAction);
                list<Deal__c> newDeals = new list<Deal__c>();
                for(Deal__c deal : deals)
                {
                    Deal__c newDeal = deal.clone(false, true);
                    newDeal.ContractV2__c = newContract.Id;
                    newDeal.Commodity__c = deal.Commodity__c;
                    insert newDeal;
                    for(cSite__c cSite : cSites)
                    {
                        if(cSite.Deal__c == deal.Id)
                        {
                            cSite__c newCSite = cSite.clone(false, true);
                            newCSite.Deal__c = newDeal.Id;
                            newSites.add(newCSite);
                        }
                    }
                    //SAL-2317 start 
                        
                // for(cPrice__c cPrice : activeCPrices){
                //     if(cPrice.Deal__c == deal.Id){
                //         cPrice__c newCPrice = cPrice.clone(false, true);
                //         newCPrice.deal__c = newDeal.Id;
                //         newPrices.add(newCPrice);
                //     }
                // }
                        
                Map<id,id> oldAndCurrentId = new Map<id,id>();  //SAL-2317
                
                // for(Volume_Strip__c volume : volumeStrips){
                //     Volume_Strip__c newVolume = volume.clone(false, true);
                //     newVolume.deal__c = newDeal.Id;
                //     newVolumeStrip.add(newVolume);
                //     oldAndCurrentId.put(volume.id,newVolume.id);
                // }
                
                
                
                for(Volume_Strip__c volume : volumeStrips){
                    Volume_Strip__c newVolume = volume.clone(false, true);
                    newVolume.deal__c = newDeal.Id;
                    tempVolumeStripList.add(newVolume);
                }
                
                insert tempVolumeStripList;
                
                Integer count = 0;
                
                for(Volume_Strip__c volume : volumeStrips){
                    oldAndCurrentId.put(volume.id,tempVolumeStripList[count++].id);
                }
                
                for(cPrice__c cPrice : activeCPrices){
                    if(cPrice.Deal__c == deal.Id){
                        cPrice__c newCPrice = cPrice.clone(false, true);
                        newCPrice.deal__c = newDeal.Id;
                        newPrices.add(newCPrice);
                        
                        System.debug(oldAndCurrentId);
                        
                        if(oldAndCurrentId.containsKey(cPrice.volume_Strip__c)){
                            newCPrice.volume_strip__c = oldAndCurrentId.get(cPrice.volume_Strip__c);
                            System.debug('oldAndCurrentId.get(cPrice.volume_Strip__c);' + oldAndCurrentId.get(cPrice.volume_Strip__c));
                        }
                    }
                    
                }
                
                //SAL-2317 End
                } 
                 insert newSites;
                 insert newPrices;
                 insert newVolumeStrip;
                 
                 newVolumeStrip.addAll(tempVolumeStripList); //SAL-2317
                
                list<Volume_Strip__c> newSiteVolumeStrip = new list<Volume_Strip__c>();
                for(cSite__c cSite : newSites){
                    for(Volume_Strip__c vStrip : siteVolumes){
                        if(cSite.site__c == vStrip.CSite__r.Site__c){
                            Volume_Strip__c newVolume = vStrip.clone(false, true);      
                            newVolume.CSite__c = cSite.id;
                            newSiteVolumeStrip.add(newVolume);
                            System.debug('AmendmentCompleted - Adding a New Volume Strip for Site Volumes - newVolume = ' + newVolume);
                        }    
                    }
                }
                System.debug('AmendmentCompleted - Inserting Volumes - newSiteVolumeStrip = ' + newSiteVolumeStrip);
                 insert newSiteVolumeStrip;
                
            }
            else
            {
                newContract = create.PartialAssignment(contract, amendment, assignmentAction);
                system.debug(activeCPrices);
                
                list<Deal__c> newDeals = new list<Deal__c>();
                list<Id> partialSites = new list<Id>();
                
                for(Deal__c deal : deals)
                {
                    Deal__c newDeal = new Deal__c(ContractV2__c = newContract.Id, Commodity__c = deal.commodity__c);
                    newDeal.ContractV2__c = newContract.Id;
                    newDeal.Commodity__c = deal.Commodity__c;
                    insert newDeal;
                    for(Amendment_ActionV2__c action : actions)
                    {
                        if(action.type__c == 'Dunning' || action.type__c == 'FMO')
                        {
                            system.debug(cSites);
                            if(action.site__r.Commodity__c == deal.commodity__c)
                            {
                                updateCSite( newDeal, action, newSites, cSites, assignmentAction,  ca, updateSites, amendment, partialSites);
                            }
                        }
                    }
                    for(cPrice__c cPrice : activeCPrices)
                    {
                        if(cPrice.Deal__c == deal.Id)
                        {
                            cPrice__c newCPrice = cPrice.clone(false, true);
                            newCPrice.deal__c = newDeal.Id;

                            newPrices.add(newCPrice);
                        }
                    }
                    if(contract.Opportunity__r.E_Product__c != 'FPVV')
                    {
                        Volume_Strip__c newVolume = new Volume_Strip__c(January__c = 0, February__c = 0, March__c = 0, April__c = 0, May__c = 0, June__c = 0, July__c = 0, August__c = 0, September__c = 0, October__c = 0, November__c = 0, December__c = 0);
                        newVolume.deal__c = newDeal.Id;
                        newVolume.Effective_Start_Date__c = volumeStrips[0].Effective_Start_Date__c;
                        newVolume.Effective_End_Date__c = volumeStrips[0].Effective_End_Date__c;
                        for(Volume_Strip__c historicalVolumes : [SELECT Id, January__c, February__c, March__c, April__c, May__c, June__c, July__c, August__c, September__c, October__c, November__c, December__c, Total__c FROM Volume_Strip__c WHERE Site__c in : partialSites AND type__c = 'SAS' AND (Status__c = 'Active' OR Status__c = 'Future')])
                        {
                            historicalVolumes(newVolume,historicalVolumes); 
                        }
                        newVolumeStrip.add(newVolume);
                    }
                    else
                    {
                        nonHistoricalVolumes(newVolumeStrip,volumeStrips,newDeal); 
                    }
                } 
                    insert newSites;
                    insert newPrices;
                    insert newVolumeStrip;
                    update updateSites;
                
                list<Id> siteIds = new list<Id>();
                for(cSite__c site : newSites)
                {
                    siteIds.add(site.Site__r.Id);
                }
                list<Volume_Strip__c> newSiteVolumeStrip = new list<Volume_Strip__c>();
                for(cSite__c cSite : newSites){
                    for(Volume_Strip__c vStrip : siteVolumes){
                        if(cSite.site__c == vStrip.CSite__r.Site__c){
                            Volume_Strip__c newVolume = vStrip.clone(false, true);      
                            newVolume.CSite__c = cSite.id;
                            newVolume.Type__c = 'Historical';
                            newSiteVolumeStrip.add(newVolume);
                            System.debug('AmendmentCompleted - Adding a New Volume Strip for Site Volumes - newVolume = ' + newVolume);
                        }    
                    }
                }
                System.debug('AmendmentCompleted - Inserting Volumes - newSiteVolumeStrip = ' + newSiteVolumeStrip);
              insert newSiteVolumeStrip;
                
            } 
        }
        else
        {
            system.debug(actions);
             
             System.debug('REFFFFF11:'+amendment.SAP_Ref_Num__c);
            for(Amendment_ActionV2__c action : actions){
                for(cSite__c site : cSites){
                    if(action.type__c == 'Dunning'){
                    action.Status__c = 'Complete';
                    processDropSites(cSites,actions,'Dunning');
                    
                        site.SAP_Integration_Status__c= 'Dunning request from SAP.';
                        site.Dunning__c=True;
                        site.Dunning_FMO_By_Amendment__c = true;
                        site.SAP_Contract_Number__c= '';
                    }
                            
                if(action.type__c == 'FMO'){
                    action.Status__c = 'Complete';
                    processDropSites(cSites,actions,'FMO');
                    
                    site.SAP_Integration_Status__c= 'ForceMoveOut request from SAP.';
                    site.Dunning_FMO_By_Amendment__c = true;
                    site.SAP_Contract_Number__c= '';
                        for(Amendment_ActionV2__c aa : [Select id,ETC_Override__c from Amendment_ActionV2__c where Contract_Amendment__c=:ca.id and (Type__c='FMO' OR Type__c='CA Approval')]){
                                    if(aa.ETC_Override__c!=0.00 || aa.ETC_Override__c!=Null)site.ETC_Override__c=aa.ETC_Override__c;    
                                }
                        }
                        updateSites.add(site);  
                    }
                    
                } 
                 
            

            if(!updateSites.isEmpty()){
                 update updateSites;
            }
            
            if(!newSites.isEmpty()){
                insert newSites;
                
                List<Volume_Strip__c> vStripList = processVolumeStrips(newSites, amendment, 'Historical');
                
                if(!vStripList.isEmpty()){
                insert vStripList;
                }  
            }
          
            if(!newPrices.isEmpty())
            {
              insert newPrices;
            }
                update cSites;
        }
        
        update actions;
        amendment.Amendment_Completed__c = true;
        update amendment;
        }
        catch(exception ex){
            String classInfo='AmendmentCompleted';
            String methodInfo='completeAmendmentForDunningAndFMO();';
            String logicInfo='Update contract amendment upon completing amendment action in case of Dunning and FMO Site.';
            String messageInfo='Error: ' + ex.getMessage();
            String debugInfo='Stack Trace: ' + ex.getStackTraceString();
            FPVV_Logger.FPVV_logMessage(classInfo, methodInfo, logicInfo, messageInfo,debugInfo);
        }
    }
    
    public static void historicalVolumes(Volume_Strip__c v,Volume_Strip__c hv){ 
        
        v.January__c += hv.January__c;
        v.February__c += hv.February__c;
        v.March__c += hv.March__c;
        v.April__c += hv.April__c;
        v.May__c += hv.May__c;
        v.June__c += hv.June__c;
        v.July__c += hv.July__c;
        v.August__c += hv.August__c;
        v.September__c += hv.September__c;
        v.October__c += hv.October__c;
        v.November__c += hv.November__c;
        v.December__c += hv.December__c;
         
    }
    
    public static void nonHistoricalVolumes(list<Volume_Strip__c> newVolumeStrip,list<Volume_Strip__c> volumeStrips,Deal__c newDeal){
      
        Volume_Strip__c newVolume = new Volume_Strip__c();
        newVolume.Effective_Start_Date__c = volumeStrips[0].Effective_Start_Date__c;
        newVolume.Effective_End_Date__c = volumeStrips[0].Effective_End_Date__c;
        newVolume.deal__c = newDeal.Id;
        newVolume.type__c = 'Contract';
        newVolume.January__c = 0;
        newVolume.February__c = 0;
        newVolume.March__c = 0;
        newVolume.April__c = 0;
        newVolume.May__c = 0;
        newVolume.June__c = 0;
        newVolume.July__c = 0;
        newVolume.August__c = 0;
        newVolume.September__c = 0;
        newVolume.October__c = 0;
        newVolume.November__c = 0;
        newVolume.December__c = 0;
        newVolumeStrip.add(newVolume);
         
    }
    
    //Price Method
    // public static void contractPrice(Amendment_ActionV2__c a, list<Quote_Term_Price__c> qtps,list<cPrice__c> activeCPrices,list<Deal__c> deals,Contract_Amendment__c amendment,list<cPrice__c> newPrices){
      
    //     a.Status__c = 'Complete';
    //     a.Effective_Date__c = qtps[0].Start_Date__c;
    //     system.debug('entered price section');
    //     cPrice__c newPrice = new cPrice__c();
    //     system.debug(qtps);
    //     system.debug(qtps.size());
    //     system.debug('@AAAAPPPP@'+activeCprices); 
    //     for(cPrice__c activeCPrice : activeCPrices)
    //     {
    //         activeCPrice.Effective_End_Date__c = qtps[0].Start_Date__c - 1;
    //         System.debug('activeCPrice = ' + activeCPrice.id);
            
    //     }
    //     update activeCPrices;
    //     if(qtps.size() > 1)
    //     {
    //         for(Quote_Term_Price__c qtp : qtps)
    //         {
    //             newPrice.deal__c = deals[0].Id;
    //             newPrice.Load_Shape__c = qtp.Load_Shape__c;
    //             newPrice.Effective_Start_Date__c = qtp.Start_Date__c;
    //             newPrice.Effective_End_Date__c = qtp.End_Date__c;
    //             newPrice.Product__c = amendment.Enmax_Quote__r.Product__c;
    //             newPrice.Term__c = qtp.Term__c;
    //             newPrice.Retail_Price__c = qtp.Retail_price__c;
    //             newPrice.Transfer_Price__c = qtp.Transfer_Price__c;
    //             newPrices.add(newPrice);
    //         }
    //     }
    //     else
    //     {
    //         newPrice.deal__c = deals[0].Id;
    //         newPrice.Load_Shape__c = qtps[0].Load_Shape__c;
    //         newPrice.Effective_Start_Date__c = qtps[0].Start_Date__c;
    //         newPrice.Effective_End_Date__c = qtps[0].End_Date__c;
    //         newPrice.Product__c = amendment.Enmax_Quote__r.Product__c;
    //         newPrice.Term__c = qtps[0].Term__c;
    //         newPrice.Retail_Price__c = qtps[0].Retail_price__c;
    //         newPrice.Transfer_Price__c = qtps[0].Transfer_Price__c;
    //         newPrices.add(newPrice);
    //     } 
    // }
    
    //Volume method
    // public static void contractVolume(Amendment_ActionV2__c action,list<Quote_Term_Price__c> qtps,list<Volume_Strip__c> volumeStrips,list<Volume_Strip__c> newVolumeStrip,list<Deal__c> deals){
    //     system.debug('entered volume section');
    //     action.Status__c = 'Complete';
    //     action.Effective_Date__c = qtps[0].Start_Date__c;
    //     for(Volume_Strip__c volumeStrip : volumeStrips)
    //     {
    //         volumeStrip.Effective_End_Date__c = qtps[0].Start_Date__c - 1;
    //     }
    //     update volumeStrips;
    //     Volume_Strip__c newVolume = new Volume_Strip__c();
    //     newVolume.Deal__c = deals[0].Id;
    //     newVolume.Type__c = 'Contract';
    //     newVolume.Effective_Start_Date__c = qtps[0].Start_Date__c;
    //     newVolume.Effective_End_Date__c = qtps[0].End_Date__c;
    //     newVolume.January__c = qtps[0].January__c;
    //     newVolume.February__c = qtps[0].February__c;
    //     newVolume.March__c = qtps[0].March__c;
    //     newVolume.April__c = qtps[0].April__c;
    //     newVolume.May__c = qtps[0].May__c;
    //     newVolume.June__c = qtps[0].June__c;
    //     newVolume.July__c = qtps[0].July__c;
    //     newVolume.August__c = qtps[0].August__c;
    //     newVolume.September__c = qtps[0].September__c;
    //     newVolume.October__c = qtps[0].October__c;
    //     newVolume.November__c = qtps[0].November__c;
    //     newVolume.December__c = qtps[0].December__c;
    //     newVolumeStrip.add(newVolume);
    // }
    
    //Extesion method
//     public static void contractExtension(Amendment_ActionV2__c action,List<cPrice__c > activeCPrices, list<Quote_Term_Price__c > qtps, list<Volume_Strip__c > volumeStrips, list<CSite__c > cSites){
//         action.Status__c = 'Complete';
//         for(cPrice__c activeCPrice : activeCPrices)
//         {
//             activeCPrice.Effective_End_Date__c = qtps[0].End_Date__c;
//             update activeCprices;
//         }
//         for(Volume_Strip__c volumeStrip : volumeStrips)
//         {
//             volumeStrip.Effective_End_Date__c = qtps[0].End_Date__c;
//              update volumeStrips;
//         }
//         for(CSite__c site : cSites)
//         {
//             site.Effective_End_Date__c = qtps[0].End_Date__c;
//             update cSites;
//         }
//   }     
        //Updating csite through fmo/dunning
        public static void updateCSite(Deal__c newDeal,Amendment_ActionV2__c action,list<cSite__C> newSites,list<CSite__c > cSites,Amendment_ActionV2__C assignmentAction,Contract_Amendment__c ca,list<cSite__c> updateSites,Contract_Amendment__c amendment,list<Id> partialSites){
            system.debug('entered commodity check statement');
            cSite__c newSite = new cSite__c();
            newSite.Deal__c = newDeal.Id;
            newSite.Site__c = action.Site__c;
            newSite.Effective_Start_Date__c = action.Effective_Date__c;
            newSite.Effective_End_Date__c = amendment.Contract__r.Contract_End_Date__c;
            newSite.Original_End_Date__c = amendment.Contract__r.Contract_End_Date__c; //SNF-269
            newSites.add(newSite);
            partialSites.add(action.Site__c);
            for(cSite__c site : cSites)
            {
                system.debug(site.site__c);
                system.debug(action.Site__c);
                if(action.site__c == site.site__c)
                {
                    system.debug('Loop 1');
                    site.Effective_End_Date__c = assignmentAction.Effective_Date__c - 1; 
                    site.SAP_Interaction_Record_Number__c=ca.SAP_Ref_Num__c;
                    
                    if(action.type__c == 'Dunning'){
                        site.SAP_Integration_Status__c= 'Dunning request from SAP.';
                        site.Dunning__c=True;//Case-00028240 - updated Dunning True
                    }
                    system.debug('Loop 2');
                    if(action.type__c == 'FMO'){//#SR-75024 OR #SR-74024
                        site.SAP_Integration_Status__c= 'ForceMoveOut request from SAP.';
                        for(Amendment_ActionV2__c aa : [Select id,ETC_Override__c from Amendment_ActionV2__c where Contract_Amendment__c=:ca.id and (Type__c='FMO' OR Type__c='CA Approval')]){
                            if(aa.ETC_Override__c!=0.00 || aa.ETC_Override__c!=Null)site.ETC_Override__c=aa.ETC_Override__c;    
                            system.debug('Loop 3');
                            
                        }
                    }
                    system.debug('Loop 4');
                    site.Dunning_FMO_By_Amendment__c= true;
                    site.Dropped_By_Amendment__c = true;
                    site.SAP_Contract_Number__c= '';
                    updateSites.add(site);
                    system.debug('Loop 5');
                }
                
            }
        }
       


    
}
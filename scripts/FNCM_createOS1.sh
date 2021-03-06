#!/bin/bash

# This script creates an Object Store w/ Workflow system and an Advanced Storage Area 
# It also creates a CSS Server, Index Area and enables CBR on the Object Store

# Extract parameter values from the command line
cpeIngress=$1
CPE_PortNumber=$2
CPE_BootstrapUserPassword=$3

# Computed parameter values
cpeMachine_nodeName=$(runuser -l ec2-user -c "kubectl get ingress/$cpeIngress -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}'")

# Pre-defined parameter values
CPE_BootstrapUsername="P8Admin"
cos_OSName="OS1"
jdbcDataSourceName="OS1DS"
jdbcDataSourceXAName="OS1DSXA"
cos_AdminUsers="P8Admins"
cos_Users="GeneralUsers"

# Worklow system parameter values
PE_tableSpace="PEDATA_TS"
PE_CONNPT_NAME="OS1Connection"
PE_REGION_Name="OS1Region1"
PE_REGION_NUMBER="1"

# Advanced Storage Area parameter values
ASA_Storage_Device="OS1_File_System_Storage"
ASA_Root_Path="/opt/ibm/asa/OS1_StorageArea1"
ASA_Name="File_System_Storage"

# CSS parameter values
CSS_site_name="Initial Site"
CSS_text_search_server_name="OS1-CSS-1"
CSS_affinity_group_name="OS1_Affinity_Group"
CSS_text_search_server_status="0"
CSS_text_search_server_mode="0"
CSS_text_search_server_ssl_enable="true"
CSS_text_search_server_credential="RNUNEWc="
CSS_text_search_server_host="fncm-css-svc"
CSS_text_search_server_port="8199"
CSS_index_area_name="OS1_index_area"
CSS_root_dir="/opt/ibm/indexareas"
CSS_max_indexes="20"
CSS_max_objects_per_index="10000"
CSS_class_name="Document"
CSS_indexing_languages="en"
CSS_temporary_work_area="/opt/ibm/textext"

# Set timeout iterations in 30s intervals
TIME_OUT=30

# Set Java classpath to include required jar files
LIBCLASSPATH="/home/ec2-user/cpelib/CPEUtils.jar:/home/ec2-user/cpelib/Jace.jar:/home/ec2-user/cpelib/log4j.jar:/home/ec2-user/cpelib/stax-api.jar:/home/ec2-user/cpelib/xercesImpl.jar:/home/ec2-user/cpelib/xlxpScanner.jar:/home/ec2-user/cpelib/xlxpScannerUtils.jar"

# Restart CPE pods 
# Pods=$(runuser -l ec2-user -c "kubectl get pods | grep cpe")
# cpePods=$(echo $Pods | awk '{print $1 " " $6 " " $11}')
# for i in $cpePods; do
#         runuser -l ec2-user -c "kubectl delete pod $i"
# done

# i=0
# while(($i<$TIME_OUT))
# do
#     PodsOnline=$(runuser -l ec2-user -c "kubectl get deployment $deploymentName -o jsonpath='{.status.readyReplicas}'")
#     if [[ $PodsOnline -eq "3" ]]; then
#         break
#     else
#         echo "$i. CPE pods have not started yet, wait 30 seconds and retry again...."
#         sleep 30s
#         let i++
#     fi
# done
# if [[ $i -eq $TIME_OUT ]]; then
#         echo "CPE not available. Exiting..."
#         exit 1
# fi

######### Use a single CPE node for Object Store creation ############
# Get the CPE replica set name
deployments=$(runuser -l ec2-user -c "kubectl get deployments | grep cpe")
deploymentName=$(echo $deployments | awk '{print $1}')

# Set number of replcas to 1
deployments=$(runuser -l ec2-user -c "kubectl scale --replicas=1 deployment.v1.apps/$deploymentName")

# Check whether the number of replicas is scaled down to 1
i=0
while(($i<$TIME_OUT))
do
        PodsOnline=$(runuser -l ec2-user -c "kubectl get deployment $deploymentName -o jsonpath='{.status.readyReplicas}'")
        echo "# Pods Online = " $PodsOnline
        if [[ $PodsOnline -eq "1" ]]; then
                break
        else
        echo "$i. CPE pods have not yet scaled down, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "CPE pods cannot be scaled down successfully. Exiting..."
        exit 1
fi

# Determine the Liberty and FileNet log locations
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    CPE_LogLocation="/data/ecm/cpe/logstore/$CPE_PodName"
    FN_LogLocation="/data/ecm/cpe/fnlogstore/$CPE_PodName"
    if [[ -f $CPE_LogLocation/messages.log && -f $FN_LogLocation/p8_server_error.log ]]; then
        break
    else
        echo "$i. CPE pods have not started yet, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "CPE not available. Exiting..."
        exit 1
fi

# Check whether CPE Domain is ready - then create the Object Store
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    CPE_LogLocation="/data/ecm/cpe/logstore/$CPE_PodName"
    isDomainReady=$(cat $CPE_LogLocation/messages.log | grep "PE Server started")
    if [[ "$isDomainReady" != "" ]] ;then
        sleep 30s
        java -cp $LIBCLASSPATH com.ibm.CETools 'createObjectStore' $cpeMachine_nodeName  $CPE_PortNumber $CPE_BootstrapUsername $CPE_BootstrapUserPassword $cos_OSName $jdbcDataSourceName $jdbcDataSourceXAName $cos_AdminUsers $cos_Users '' ''
        break
    else
        echo "$i. CPE Domain is not yet ready, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "CPE did not start successfully. Exiting..."
        exit 1
fi

# Check whether Object Store is ready - then create the Workflow system
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    FN_LogLocation="/data/ecm/cpe/fnlogstore/$CPE_PodName"
    isOSReady=$(cat $FN_LogLocation/p8_server_error.log | grep "Starting queue dispatching" | grep "QueueItemDispatcher" )
    if [[ "$isOSReady" != "" ]] ;then
        wf_response=$(curl -u $CPE_BootstrapUsername:$CPE_BootstrapUserPassword -H "Content-type: application/json" -X POST -i "http://$cpeMachine_nodeName:$CPE_PortNumber/cpe/init/v1/objectstores/$cos_OSName/workflow" -d "{ \"adminGroup\": \"$cos_AdminUsers\", \"configGroup\": \"$cos_AdminUsers\", \"dataTableSpace\": \"$PE_tableSpace\", \"connectionPointName\": \"$PE_CONNPT_NAME\", \"regionName\": \"$PE_REGION_Name\",  \"regionNumber\": \"$PE_REGION_NUMBER\", \"dateTimeMask\": \"mm/dd/yy hh:tt am\", \"locale\": \"en\" }")
        echo "Workflow system created successfully."
        break
    else
        echo "$i. Object Store is not yet ready, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "Object Store was not created successfully. Exiting..."
        exit 1
fi

# Create an Advanced Storge Area - check whether Object Store is ready
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    FN_LogLocation="/data/ecm/cpe/fnlogstore/$CPE_PodName"
    isOSReady=$(cat $FN_LogLocation/p8_server_error.log | grep "Starting queue dispatching" | grep "QueueItemDispatcher" )
    if [[ "$isOSReady" != "" ]] ;then
        asa_response=$(curl -u $CPE_BootstrapUsername:$CPE_BootstrapUserPassword -H "Content-type: application/json" -X POST -i "http://$cpeMachine_nodeName:$CPE_PortNumber/cpe/init/v1/objectstores/$cos_OSName/advancedstorageareas" -d "{ \"fileSystemStorageDevices\": [ { \"fileSystemStorageDeviceName\": \"$ASA_Storage_Device\", \"rootDirectoryPath\": \"$ASA_Root_Path\" } ], \"storageAreaName\": \"$ASA_Name\" }")
        echo "Advanced Storage Area created successfully."
        break
    else
        echo "$i. Object Store is not yet ready, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "Object Store was not created successfully. Exiting..."
        exit 1
fi

# Configure CSS Search - when CPE Domain is ready
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    CPE_LogLocation="/data/ecm/cpe/logstore/$CPE_PodName"
    isDomainReady=$(cat $CPE_LogLocation/messages.log | grep "PE Server started")
    if [[ "$isDomainReady" != "" ]] ;then
        css_search=$(curl -u $CPE_BootstrapUsername:$CPE_BootstrapUserPassword -H "Content-Type: application/json" -X POST -i "http://$cpeMachine_nodeName:$CPE_PortNumber/cpe/init/v1/CSS/domain/cssServers" -d "{ \"siteName\": \"$CSS_site_name\", \"affinityGroupName\": \"$CSS_affinity_group_name\", \"textSearchServerName\": \"$CSS_text_search_server_name\", \"textSearchServerStatus\": \"$CSS_text_search_server_status\", \"textSearchServerCredential\": \"$CSS_text_search_server_credential\", \"textSearchServerHost\": \"$CSS_text_search_server_host\", \"textSearchServerPort\": \"$CSS_text_search_server_port\", \"textSearchServerMode\": \"$CSS_text_search_server_mode\", \"sslEnabled\": \"$CSS_text_search_server_ssl_enable\" }")
        echo "CSS server created successfully."
        break
    else
        echo "$i. CPE Domain is not yet ready, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "Object Store was not created successfully. Exiting..."
        exit 1
fi

# Create Index Area in Object Store - when Object Store is ready
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    FN_LogLocation="/data/ecm/cpe/fnlogstore/$CPE_PodName"
    isOSReady=$(cat $FN_LogLocation/p8_server_error.log | grep "Starting queue dispatching" | grep "QueueItemDispatcher" )
    if [[ "$isOSReady" != "" ]] ;then
        css_index=$(curl -u $CPE_BootstrapUsername:$CPE_BootstrapUserPassword -H "Content-Type: application/json" -X POST -i "http://$cpeMachine_nodeName:$CPE_PortNumber/cpe/init/v1/CSS/objectstores/$cos_OSName/indexAreas" -d "{ \"affinityGroupName\": \"$CSS_affinity_group_name\", \"rootDir\": \"$CSS_root_dir\", \"maxIndexes\": \"$CSS_max_indexes\", \"maxObjectsPerIndex\": \"$CSS_max_objects_per_index\", \"indexAreaName\": \"$CSS_index_area_name\" }")
        echo "Index Area created successfully."
        break
    else
        echo "$i. Object Store is not yet ready, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "Object Store was not created successfully. Exiting..."
        exit 1
fi

# Enable CBR on Object Store - when Object Store is ready
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    FN_LogLocation="/data/ecm/cpe/fnlogstore/$CPE_PodName"
    isOSReady=$(cat $FN_LogLocation/p8_server_error.log | grep "Starting queue dispatching" | grep "QueueItemDispatcher" )
    if [[ "$isOSReady" != "" ]] ;then
        css_cbr=$(curl -u $CPE_BootstrapUsername:$CPE_BootstrapUserPassword -H "Content-Type: application/json" -X PUT -i "http://$cpeMachine_nodeName:$CPE_PortNumber/cpe/init/v1/CSS/objectstores/$cos_OSName/classnames/$CSS_class_name/languages/$CSS_indexing_languages" -d "{ \"temporaryWorkArea\": \"$CSS_temporary_work_area\" }")
        echo "CBR on object store created successfully."
        break
    else
        echo "$i. Object Store is not yet ready, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "Object Store was not created successfully. Exiting..."
        exit 1
fi

# Create a sample folder - when Object Store is ready
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    FN_LogLocation="/data/ecm/cpe/fnlogstore/$CPE_PodName"
    isOSReady=$(cat $FN_LogLocation/p8_server_error.log | grep "Starting queue dispatching" | grep "QueueItemDispatcher" )
    if [[ "$isOSReady" != "" ]] ;then
        os1_folder=$(curl -u $CPE_BootstrapUsername:$CPE_BootstrapUserPassword -H "Content-Type: application/json" -X POST -i "http://$cpeMachine_nodeName:$CPE_PortNumber/cpe/init/v1/Objects/objectstores/$cos_OSName/folders" -d "{ \"folderPath\": \"/Sample_Folder\" }")
        echo "Sample folder was created successfully."
        break
    else
        echo "$i. Object Store is not yet ready, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "Object Store was not created successfully. Exiting..."
        exit 1
fi

# Create a sample document - when Object Store is ready
i=0
while(($i<$TIME_OUT))
do
    PodName=$(runuser -l ec2-user -c "kubectl get pods | grep cpe | grep 1/1")
    CPE_PodName=$(echo $PodName | awk '{print $1}')
    FN_LogLocation="/data/ecm/cpe/fnlogstore/$CPE_PodName"
    isOSReady=$(cat $FN_LogLocation/p8_server_error.log | grep "Starting queue dispatching" | grep "QueueItemDispatcher" )
    if [[ "$isOSReady" != "" ]] ;then
        os1_document=$(curl -u $CPE_BootstrapUsername:$CPE_BootstrapUserPassword -H "Content-Type: application/json" -X POST -i "http://$cpeMachine_nodeName:$CPE_PortNumber/cpe/init/v1/Objects/objectstores/$cos_OSName/documents" -d "{ \"folderName\": \"/Sample_Folder\", \"documentTitle\": \"FileNet Content Manager Documentation\", \"className\": \"Document\", \"documentContent\": \"IBM FileNet P8 Platform V5.5x documentation: https://www.ibm.com/support/knowledgecenter/SSNW2F_5.5.0/com.ibm.p8toc.doc/welcome_p8.htm\", \"documentContentName\": \"IBM_FileNet_documentation.txt\" }")
        echo "Sample text document was created successfully."
        break
    else
        echo "$i. Object Store is not yet ready, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "Object Store was not created successfully. Exiting..."
        exit 1
fi

######### Object Store creation complete - start up the other 2 CPE nodes ############
# Set number of replicas to 3
deployments=$(runuser -l ec2-user -c "kubectl scale --replicas=3 deployment.v1.apps/$deploymentName")

# Check the number of replicas
i=0
while(($i<$TIME_OUT))
do
        PodsOnline=$(runuser -l ec2-user -c "kubectl get deployment $deploymentName -o jsonpath='{.status.readyReplicas}'")
        echo "# Pods Online = " $PodsOnline
        if [[ $PodsOnline -eq "3" ]]; then
                break
        else
        echo "$i. CPE pods have not started yet, wait 30 seconds and retry again...."
        sleep 30s
        let i++
    fi
done
if [[ $i -eq $TIME_OUT ]]; then
        echo "CPE pods has not restarted successfully. Exiting..."
        exit 1
fi

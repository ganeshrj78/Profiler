#!/bin/bash

####################################################################################
# This Batch Script will Extract  the following metrics from a Hadoop Cluster :
# ------------------------------------------------------------------
#
# 1. YARN Application execution, Host , metrics and Scheduler Information 
#
# 2. If the Distribution is HDP, then it will extract
#     -  the blueprint from Ambari 
#     -  Ranger policies if Ranger is Used 
#
# 3. If the Distribution is CDP, then it will extract
#     -  the Services from CM        
#     -  Impala logs based on the input dates 
#
#####################################################################################


. `dirname ${0}`/profiler.conf 

## Init Variables 

export curr_date=`date +"%Y%m%d_%H%M%S"`
export curr_impala_batch_dt=`date +"%Y-%m-%d"`

export output_dir=`dirname ${0}`/Output/

export CURL='curl ' 
export http='http://'
export kerburl=' --negotiate -u : '

export clusterinfo='/ws/v1/cluster/info'
export rmapps='/ws/v1/cluster/apps'
export rmmetrics='/ws/v1/cluster/metrics'
export rmscheduler='/ws/v1/cluster/scheduler'
export rmnodes='/ws/v1/cluster/nodes'

check_kerberos()  { 

    if [ "$IS_SECURE" == "Y" ]; then 
        CURL="$CURL -k"
        http="https://"
    else 
        CURL="$CURL " 
        http="http://"
    fi 

    if [ "$IS_KERBERIZED" == "Y" ]; then

        echo " Kerberos is set as True. Make sure to Kinit before executing the script. Current Credential Cache is ... "
        eval klist
        echo "                                                                   " 

	if [ "$GOT_KEYTAB" == "Y" ]; then 
	    echo " Initializing with Keytab provided ..... " 
	    kinit="kinit -kt $KEYTAB_PATH/$KEYTAB $PRINCIPAL"
	    eval $kinit
            eval klist

	#else 
            #echo " Press Enter to Continue or Ctrl+C to cancel  .... "
            #read input
        fi 

        ## Patch up Kerberos URL 
        url=$(echo $CURL$kerburl$http)
    else 
        ## Patch up Kerberos URL 
        url=$(echo $CURL$http)
    fi
}

check_active_rm() { 

    ##echo $RM_SERVER_URL

    activermserver=""
    rmserver=$(echo $RM_SERVER_URL | tr "," "\n")
  
     
    for rms in $rmserver 
    do 
       echo $rms 
       clusterinfourl=$url$rms:$RM_SERVER_PORT$clusterinfo
       echo $clusterinfourl

       activerm=`$clusterinfourl  |grep ACTIVE |wc -l`

       #echo $activerm

       if [ $activerm == 1 ]; then 
           activerm_url=$url$rms:$RM_SERVER_PORT 
           break
       fi
    done
   
    echo "Active RM URL is : " $activerm_url

    if [ "$activerm_url" == "" ]; then 
         echo "Active Resource manager URL not found ... aborting the process ...  " 
         exit 1 

    fi 

}

extract_yarn_appls() {

    #apps=`$activerm_url$rmapps`
    appdump=YarnApplicationDump_$curr_date.json
    #echo $apps >  $output_dir$appdump

    eval $activerm_url$rmapps > $output_dir$appdump      
    exit 

}


extract_yarn_hosts()  {

    rmnodes=`$activerm_url$rmnodes`
    nodedump=YarnNodesDump_$curr_date.json

    echo $rmnodes >  $output_dir$nodedump

}

extract_yarn_metrics()  {

    rmmetrics=`$activerm_url$rmmetrics`
    metricsdump=YarnMetricsDump_$curr_date.json

    echo $rmmetrics >  $output_dir$metricsdump

}



extract_yarn_scheduler()  {

    rmscheduler=`$activerm_url$rmscheduler`
    schedulerdump=YarnSchedulerDump_$curr_date.json

    echo $rmscheduler >  $output_dir$schedulerdump

}


extract_yarn() { 

    check_active_rm
    extract_yarn_appls

    ### Extract additional YARN Details only during initial run 
    
    if [ "$INITIAL_EXEC" == "Y" ]; then 
        extract_yarn_hosts
        extract_yarn_metrics
        extract_yarn_scheduler
    fi

}

extract_ambari_bp() { 
    echo " Extracting Ambari Blueprint .. "

    if [ $AMBARI_SECURED == "Y" ]; then 
        CURL="$CURL -k"
        http="https://"
    else 
        CURL="$CURL " 
        http="http://"
    fi 

    ### Ambari Metrics 
    bpurl="$CURL -X GET -u $AMBARI_ADMIN_USERID:$AMBARI_ADMIN_PASSWORD $http$AMBARI_SERVER:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME?format=blueprint"
    ambariHosts="$CURL -X GET -u $AMBARI_ADMIN_USERID:$AMBARI_ADMIN_PASSWORD $http$AMBARI_SERVER:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/hosts?fields=Hosts/cpu_count,Hosts/disk_info,Hosts/total_mem,Hosts/os_type"
    ambariServices="$CURL -X GET -u $AMBARI_ADMIN_USERID:$AMBARI_ADMIN_PASSWORD $http$AMBARI_SERVER:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/services"
    ambariComponents="$CURL -X GET -u $AMBARI_ADMIN_USERID:$AMBARI_ADMIN_PASSWORD $http$AMBARI_SERVER:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/hosts?fields=host_components/host_name"
    ambariStack="$CURL -X GET -u $AMBARI_ADMIN_USERID:$AMBARI_ADMIN_PASSWORD $http$AMBARI_SERVER:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/stack_versions/1"

    ### Ambari RM and HDFS Metrics 
    
    ambariHDFS="$CURL -X GET -u $AMBARI_ADMIN_USERID:$AMBARI_ADMIN_PASSWORD $http$AMBARI_SERVER:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/services/HDFS/components/NAMENODE"
    ambariRM="$CURL -X GET -u $AMBARI_ADMIN_USERID:$AMBARI_ADMIN_PASSWORD $http$AMBARI_SERVER:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/services/YARN/components/RESOURCEMANAGER"
    ambariNM="$CURL -X GET -u $AMBARI_ADMIN_USERID:$AMBARI_ADMIN_PASSWORD $http$AMBARI_SERVER:$AMBARI_PORT/api/v1/clusters/$CLUSTER_NAME/services/YARN/components/NODEMANAGER"

    bp=`$bpurl`
    hosts=`$ambariHosts`
    services=`$ambariServices`
    components=`$ambariComponents`
    stack=`$ambariStack`

    ambarihdfs=`$ambariHDFS`
    ambarirm=`$ambariRM`
    ambarinm=`$ambariNM`


    bppath=AmbariBlueprint_$curr_date.json
    hostpath=AmbariHost_$curr_date.json
    servicepath=AmbariServices_$curr_date.json
    componentspath=AmbariComponents_$curr_date.json
    stackpath=AmbariStack_$curr_date.json


    ambarihdfspath=AmbariHDFS_$curr_date.json
    ambarirmpath=AmbariRM_$curr_date.json
    ambarinmpath=AmbariNM_$curr_date.json

    echo $bp > $output_dir$bppath
    echo $hosts > $output_dir$hostpath
    echo $components > $output_dir$componentspath
    echo $services > $output_dir$servicepath
    echo $stack > $output_dir$stackpath

    echo $ambarihdfs > $output_dir$ambarihdfspath
    echo $ambarirm > $output_dir$ambarirmpath
    echo $ambarinm > $output_dir$ambarinmpath
    
    
} 


###########################################
### Extract HDP Logs 
###########################################

extract_ranger_policies() { 
 
    if [ "$RANGER_SECURED" == "Y" ]; then
        CURL="$CURL -k"
        http="https://"
    else
        CURL="$CURL "
        http="http://"
    fi

    rangerRepos="$CURL -X GET -u $RANGER_USER:$RANGER_PWD -X GET $http$RANGER_URL:$RANGER_PORT/service/public/api/repository"
    rangerPolicies="$CURL -X GET -u $RANGER_USER:$RANGER_PWD -X GET $http$RANGER_URL:$RANGER_PORT/service/public/api/policy"


    repos=`$rangerRepos`
    policies=`$rangerPolicies`

    ranger_repos=Ranger_Repos_$curr_date.json
    ranger_policies=Ranger_Policies_$curr_date.json

    echo $repos > $output_dir$ranger_repos
    echo $policies > $output_dir$ranger_policies

}



extract_hdp() { 

    check_kerberos
    extract_yarn

    if [ "$INITIAL_EXEC" == "Y" ]; then 
       extract_ambari_bp
      

       if [ "$IS_RANGER_SETUP" == "Y" ]; then
            extract_ranger_policies
       fi 
       echo " ####################################################################################################"
       echo " NOTE: This is an Initial Extract. Please inspect the files to make sure the extracts are fine .... "
       echo " ####################################################################################################"
    fi

}


###########################################
### Extract CDP Logs
###########################################

extract_cm_info() {

    if [ "$CM_SECURED" == "Y" ]; then 
        CURL="$CURL -k"
        http="https://"
    else 
        CURL="$CURL " 
        http="http://"
    fi 

    ### Cloudera Manager Metrics

    CM_CLUSTER=`echo $CM_CLUSTER | sed 's/ /%20/g'` 

    cmservices="$CURL -X GET -u $CM_ADMIN_USER:$CM_ADMIN_PASSWORD $http$CM_SERVER_URL:$CM_SERVER_PORT/api/$CM_API_VERSION/clusters/$CM_CLUSTER/services"
    cmhost="$CURL -X GET -u $CM_ADMIN_USER:$CM_ADMIN_PASSWORD $http$CM_SERVER_URL:$CM_SERVER_PORT/api/$CM_API_VERSION/hosts"
    cmconfig="$CURL -X GET -u $CM_ADMIN_USER:$CM_ADMIN_PASSWORD $http$CM_SERVER_URL:$CM_SERVER_PORT/api/$CM_API_VERSION/cm/allHosts/config"
    cmexport="$CURL -X GET -u $CM_ADMIN_USER:$CM_ADMIN_PASSWORD $http$CM_SERVER_URL:$CM_SERVER_PORT/api/$CM_API_VERSION/clusters/$CM_CLUSTER/export"

    services=`$cmservices`
    hosts=`$cmhost`
    config=`$cmconfig`
    cmexp=`$cmexport`
    
    cm_services=cmServices_$curr_date.json
    cm_hosts=cmHosts_$curr_date.json
    cm_config=cmConfig_$curr_date.json
    cm_export=cmExport_$curr_date.json
    
    echo $services > $output_dir$cm_services
    echo $hosts > $output_dir$cm_hosts
    echo $config > $output_dir$cm_config
    echo $cmexp > $output_dir$cm_export 

}

############################################################
## Impala Extract created by : Gui Bracialli 
############################################################

extract_impala() { 

    echo "Extracting Impala Queries " 

    if [ "$CM_SECURED" == "Y" ]; then 
        CURL="$CURL -k"
        http="https://"
    else 
        CURL="$CURL " 
        http="http://"
    fi 

    CM_CLUSTER=`echo $CM_CLUSTER | sed 's/ /%20/g'` 
    BASE_URL="$http$CM_SERVER_URL:$CM_SERVER_PORT/api/$CM_API_VERSION/clusters/$CM_CLUSTER/services/$CM_IMPALA_SERVICE/impalaQueries"

    #not using date range becuase date commands are different in linux and osx
    ####echo $CM_IMPALA_EXTRACT_DATES
    ####dates=($CM_IMPALA_EXTRACT_DATES)


    if [ "$INITIAL_EXEC" == "Y" ]; then 
       dates=($CM_IMPALA_EXTRACT_DATES)
    else 
       echo "Running in Scheduled mode ... using $curr_impala_batch_dt for the extract"
       dates=($curr_impala_batch_dt)
    fi

    echo $dates
    
    for DAY in "${dates[@]}"
	do
	  for HOUR in $(seq -w 0 23)
	  do
	    for OFFSET in 0 1000 2000 3000 4000 5000
	    do
	       URL_FILTER="$BASE_URL?from=${DAY}T${HOUR}%3A00%3A00.000Z&to=${DAY}T${HOUR}%3A23%3A59.999Z&filter=&limit=1000&offset=$OFFSET"
	       echo "extracting $URL_FILTER"
	       #curl --insecure -v -u ${CM_ADMIN_USER}:${CM_ADMIN_PASSWORD} $URL_FILTER > impala_${DAY}_${HOUR}_${OFFSET}.json
	      
	       cmimpala="$CURL -X GET -u ${CM_ADMIN_USER}:${CM_ADMIN_PASSWORD} $URL_FILTER"

 	       impalaextract=`$cmimpala`
               cm_impalaext=impala_${DAY}_${HOUR}_${OFFSET}.json
	       echo $impalaextract > $output_dir$cm_impalaext

	    done
	  done
    done
  
}

extract_cdp() { 

    check_kerberos
    extract_yarn
    
    if [ "$INITIAL_EXEC" == "Y" ]; then 
       extract_cm_info
       #extract_sentry_policies

    fi

    ## Extracting Impala 
    extract_impala

    echo " #################################################################################################################"
    echo " NOTE: This is an Initial Extract.  Please inspect the files to:                                                  " 
    echo " -----  1. Make sure the extracts looks fine ....                                                                 " 
    echo "        2. Cloudera Manager Export  for  any sensitive information like user id and passwords                     "
    echo "        3. Impala extract for hard coded NPI or PHI values in the queries                                         "
    echo " #################################################################################################################"

}

##########################################################################################################
################################## START of Main Code ####################################################
##########################################################################################################

echo "Dist: "  $DISTRIBUTION

#echo " Creating Output Directory : " 
mkdir -p $output_dir

if [ "$DISTRIBUTION" == "HDP" ]; then 

      echo " Distribution is Hortonworks. About to Extact ... "       
      extract_hdp

else if [ "$DISTRIBUTION" == "CDP" ]; then 
      echo " Distribtuion is Cloudera . Starting Extract ... " 
      extract_cdp
     else 
        echo  " Invalid Distribution"
        exit 1
     fi
fi

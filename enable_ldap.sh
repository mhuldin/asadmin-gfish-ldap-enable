#!/bin/bash


domainname=$1
adminport=$2
glassfish_user=$3
host_env=$4

if [ -z "$1" ]; then
    echo >&2 "$0: ERROR: Environment variable domainname not set"
    exit 1
fi
if [ -z "$2" ]; then
    echo >&2 "$0: ERROR: Environment variable adminport not set"
    exit 1
fi
if [ -z "$3" ]; then
    echo >&2 "$0: ERROR: Environment variable glassfish_user not set"
    exit 1
fi
if [ -z "$4" ]; then
    echo >&2 "$0: ERROR: Parameter environment not set"
    exit 1
fi

#Sed in the end of the script differs pending on Glassfish Version and the reason for case below
#If upgrade to a new version we need to check whatever settings domains.xml needs.

case $3 in
	"gf31")
	;;
	"gf3")
	;;
	*)
echo	"Will not continue setting up ldap only supported by Glassfish v31 and v3"
exit
esac


if [ "$host_env" = prod ];
then
	echo "This is (prod) production according to environment parameter from GO, setting up ldap url for production"
ldap_url1="ldap://[url]"
ldap_url2="ldap://[url]"
ldap_url3="ldap://[url]"
ldap_url4="ldap://[url]"

else
	echo "Environment in GO is not set to production, using ldap servers in test"
ldap_url1="ldap://[url]"
ldap_url2="ldap://[url]"
fi

echo "Trying to enable ldap login for glassfish admin ...."
echo "                                                    "
echo "Making a copy of domain.xml to domain.xml_nodlap in /config"
echo "domain.xml can be used to revert everything but the domain needs to be restarted when domain.xml is replaced."

cp /opt/$glassfish_user-domains/$domainname/config/domain.xml /opt/$glassfish_user-domains/$domainname/config/domain.xml_nodlap

#Need to set timeout for asadmin because glassfish isn't very helpful, by export AS_ADMIN_READTIMEOUT="20000"
export AS_ADMIN_READTIMEOUT="20000"

echo "Running command to enable ldap asadmin --port=$adminport configure-ldap-for-admin --basedn dc=[name],dc=com --url $ldap_url1 --ldap-group AppServerAdmin"
asadmin --port=$adminport configure-ldap-for-admin --basedn "dc=[name],dc=com" --url $ldap_url1 --ldap-group "AppServerAdmin" > /tmp/$domainname$adminport
sleep 10

#Verifying IF ldap change was sucessful

if grep -w --quiet "Command configure-ldap-for-admin failed." /tmp/$domainname$adminport;
then
	echo "It seems like $ldap_url1 isn't accessible"
	echo "Trying a different ldap server $ldap_url2"
	echo "Running asadmin --port=$adminport configure-ldap-for-admin --basedn "dc=[name],dc=com" --url $ldap_url2 --ldap-group "AppServerAdmin""

asadmin --port=$adminport configure-ldap-for-admin --basedn "dc=[name],dc=com" --url $ldap_url2 --ldap-group "AppServerAdmin" > /tmp/$domainname$adminport
sleep 10
fi

#====================================================================================================
#
#	A fast fix for production. This should probably be a loop function instead of tons of if.
#	ldap_url1 and ldap_url2 will work 99/100.
#
#====================================================================================================

if [ "$host_env" = prod ];
then
        if grep -w --quiet "Command configure-ldap-for-admin failed." /tmp/$domainname$adminport;
then
        echo "It seems like $ldap_url2 isn't accessible"
        echo "Trying a different ldap server $ldap_url3"
	echo "Running asadmin --port=$adminport configure-ldap-for-admin --basedn "dc=[name],dc=com" --url $ldap_url3 --ldap-group "AppServerAdmin""
asadmin --port=$adminport configure-ldap-for-admin --basedn "dc=[name],dc=com" --url $ldap_url3 --ldap-group "AppServerAdmin" > /tmp/$domainname$adminport
sleep 10
fi
fi

if [ "$host_env" = prod ];
then
        if grep -w --quiet "Command configure-ldap-for-admin failed." /tmp/$domainname$adminport;
then
        echo "It seems like $ldap_url3 isn't accessible"
        echo "Trying a different ldap server $ldap_url4"
	echo "Running asadmin --port=$adminport configure-ldap-for-admin --basedn "dc=[name],dc=com" --url $ldap_url4 --ldap-group "AppServerAdmin""
asadmin --port=$adminport configure-ldap-for-admin --basedn "dc=[name],dc=com" --url $ldap_url4 --ldap-group "AppServerAdmin" > /tmp/$domainname$adminport
sleep 10
fi
fi

#==============================
# 	Production fix ends
#==============================

if grep -w --quiet "accessible" /tmp/$domainname$adminport;
then
        echo "Ldap is accessible will continue ...."
else
        echo "Ldap not accessible, cannot continue. This wonderful script aren't able to reach $ldap_url1 $ldap_url2 $ldap_url3 $ldap_url4."
	echo "Please try to re-deploy, if that isn't possible the urls above isn't responding"
	echo "Has LDAP/AD been moved? Maybe someone is working on them? But why are both down at the same time?"
	echo "Removing temp dir /tmp/$domainname$adminport"
	rm -rf /tmp/$domainname$adminport
#Removing the AS_ADMIN_READTIMEOUT and it should be back to default 3600000
	unset AS_ADMIN_READTIMEOUT
        exit 1
fi

if grep -w --quiet "The LDAP Auth Realm admin-realm was configured correctly in admin server's configuration." /tmp/$domainname$adminport;
then
        echo "Successfully added LDAP Auth Realm"
else
        echo "Failed to implement LDAP Auth Relam. Cannot continue. This wonderful script aren't able to reach $ldap_url1 $ldap_url2 $ldap_url3 $ldap_url4."
	echo "Please try to re-deploy, if that isn't possible the urls above isn't responding"
	echo "Has LDAP/AD been moved? Maybe someone is working on them? But why are both down at the same time?"
        echo "Removing temp dir /tmp/$domainname$adminport"
	rm -rf /tmp/$domainname$adminport
#Removing the AS_ADMIN_READTIMEOUT and it should be back to default 3600000
	unset AS_ADMIN_READTIMEOUT
        exit 1
fi

echo "Removing temp dir /tmp/$domainname$adminport"
rm -rf /tmp/$domainname$adminport
#Removing the AS_ADMIN_READTIMEOUT and it should be back to default 3600000
unset AS_ADMIN_READTIMEOUT

echo "Adding necessary properties in domain.xml with sed magic to fully enable ldap"

if [ "$glassfish_user" = gf31 ];
then
sed '/<property name="group-mapping" value="AppServerAdmin-&gt;asadmin">/a \          <property name="search-bind-password" value="[password]"></property>\n          <property name="assign-groups" value="AppServerAdmin"></property>\n          <property name="search-bind-dn" value="[bind name]@[name].com"></property>\n          <property name="java.naming.referral" value="follow"></property>\n          <property name="group-search-filter" value="(&amp;(objectClass=group)(member=%d))"></property>\n          <property name="search-filter" value="(&amp;(objectClass=user)(sAMAccountName=%s))"></property>' /opt/$glassfish_user-domains/$domainname/config/domain.xml > /opt/$glassfish_user-domains/$domainname/config/domain.xml_ldap

cp /opt/$glassfish_user-domains/$domainname/config/domain.xml_ldap /opt/$glassfish_user-domains/$domainname/config/domain.xml

else if [ "$glassfish_user" = gf3 ];
then
sed '/<property name="group-mapping" value="AppServerAdmin->asadmin">*.*/a \          <property name="search-bind-password" value="[password]" />\n          <property name="assign-groups" value="AppServerAdmin" />\n          <property name="search-bind-dn" value="[bind name]@[name].com" />\n          <property name="java.naming.referral" value="follow" />\n          <property name="group-search-filter" value="(&amp;(objectClass=group)(member=%d))" />\n          <property name="search-filter" value="(&amp;(objectClass=user)(sAMAccountName=%s))" />' /opt/$glassfish_user-domains/$domainname/config/domain.xml > /opt/$glassfish_user-domains/$domainname/config/domain.xml_ldap

cp /opt/$glassfish_user-domains/$domainname/config/domain.xml_ldap /opt/$glassfish_user-domains/$domainname/config/domain.xml
fi
fi

echo "Need to restart the domain to enable the settings ....."
asadmin --port=$adminport stop-domain $domainname
asadmin --port=$adminport start-domain $domainname

echo "DONE! ldap login for glassfish admin is activated"

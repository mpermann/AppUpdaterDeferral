#!/bin/bash

# The script is for patching an app with user notification before starting and supports deferrals with
# tracking. Parameter 4 is the name of the app to be patched, parameter 5 is the name of the app process, 
# parameter 6 is the policy trigger name to install the app and parameter 7 is the number of deferrals.
# The script is relatively basic and can't currently kill more than one process or patch more than one app.
# Version 1.0
# Created 04-02-2022 by Michael Permann

APP_NAME=$4
APP_PROCESS_NAME=$5
POLICY_TRIGGER_NAME=$6
MAX_DEFERRAL=$7
# Checking for app deferral plist file. If it exists, read current deferral count from file and set variable.
# If it doesn't exist, set current deferral count to 0.
if [ -e "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" ]
then
    echo "Current Deferal Count Read from plist"
    CURRENT_DEFERRAL_COUNT=$(defaults read "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" 'CurrentDeferralCount')
    echo "$CURRENT_DEFERRAL_COUNT"
else
    CURRENT_DEFERRAL_COUNT="0"
    echo "Deferral file does NOT exist. Setting CURRENT_DEFERRAL_COUNT to 0"
fi
CURRENT_USER=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ && ! /loginwindow/ { print $3 }')
USER_ID=$(/usr/bin/id -u "$CURRENT_USER")
AEA11_LOGO="/Library/Application Support/HeartlandAEA11/Images/HeartlandLogo@512px.png"
JAMF_HELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
JAMF_BINARY=$(which jamf)
TITLE="Quit Application"
DESCRIPTION="Greetings Heartland Area Education Agency Staff

An update for $APP_NAME is available.  Please return to $APP_NAME and save your work and quit the application BEFORE returning here and clicking the \"OK\" button to proceed with the update. Caution: your work could be lost if you don't save it and quit $APP_NAME before clicking the \"OK\" button.

You may click the \"Cancel\" button to defer this update. You can defer a maximum of $MAX_DEFERRAL times. You have deferred ${CURRENT_DEFERRAL_COUNT} times.

Thanks! - IT Department"
TITLE2="Update Complete"
DESCRIPTION2="Thank You! 

$APP_NAME has been updated on your computer. You may relaunch it now if you wish."
BUTTON1="OK"
BUTTON2="Cancel"
DEFAULT_BUTTON="2"
# Checking for app deferral plist file. If it doesn't exist, create it.
if [ ! -e "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" ]
then
/bin/cat > "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>MaxDeferral</key><integer>${MAX_DEFERRAL}</integer><key>CurrentDeferralCount</key><integer>0</integer></dict></plist>
EOF
else
echo "File already exists. Skipping plist creation"
fi

CURRENT_DEFERRAL_COUNT=$(defaults read "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" 'CurrentDeferralCount')
echo "$CURRENT_DEFERRAL_COUNT"
echo "$APP_NAME"
echo "$APP_PROCESS_NAME"
echo "$POLICY_TRIGGER_NAME"

APP_PROCESS_ID=$(/bin/ps ax | /usr/bin/pgrep -x "$APP_PROCESS_NAME" | /usr/bin/grep -v grep | /usr/bin/awk '{ print $1 }')
echo "$APP_NAME process ID $APP_PROCESS_ID"

if [ -z "$APP_PROCESS_ID" ] # Check whether app is running by testing if string length of process id is zero
then 
    echo "App NOT running so silently install app"
    "$JAMF_BINARY" policy -event "$POLICY_TRIGGER_NAME"
    if [ -e "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" ]
    then
        echo "Deferal file exists and needs removed"
        rm -rf "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" 
    else
        echo "Deferral file does NOT exist. Skipping plist deletion."
    fi
    exit 0
else
    DIALOG=$(/bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CURRENT_USER" "$JAMF_HELPER" -windowType utility -windowPosition lr -title "$TITLE" -description "$DESCRIPTION" -icon "$AEA11_LOGO" -button1 "$BUTTON1" -button2 "$BUTTON2" -defaultButton "$DEFAULT_BUTTON")
    if [[ "$DIALOG" = "2" && $CURRENT_DEFERRAL_COUNT < $MAX_DEFERRAL ]] # Check if the default cancel button was clicked
    then
        echo "User chose $BUTTON2 so deferring install"
        CURRENT_DEFERRAL_COUNT=$((CURRENT_DEFERRAL_COUNT + 1))
        defaults write "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" 'CurrentDeferralCount' "$CURRENT_DEFERRAL_COUNT"
        exit 1
    else
        echo "User chose $BUTTON1 so proceeding with install"
        APP_PROCESS_ID=$(/bin/ps ax | /usr/bin/pgrep -x "$APP_PROCESS_NAME" | /usr/bin/grep -v grep | /usr/bin/awk '{ print $1 }')
        echo "$APP_NAME process ID $APP_PROCESS_ID"
        if [ -z "$APP_PROCESS_ID" ] # Check whether app is running by testing if string length of process id is zero
        then
            echo "User chose $BUTTON1 and app NOT running so proceed with install"
            "$JAMF_BINARY" policy -event "$POLICY_TRIGGER_NAME"
            # Add message it's safe to re-open app
            /bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CURRENT_USER" "$JAMF_HELPER" -windowType utility -windowPosition lr -title "$TITLE2" -description "$DESCRIPTION2" -icon "$AEA11_LOGO" -button1 "$BUTTON1" -defaultButton "1"
            if [ -e "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" ]
            then
                echo "Deferal file exists and needs removed"
                rm -rf "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" 
            else
                echo "Deferral file does NOT exist. Skipping plist deletion."
            fi
            exit 0
        else
            echo "User chose $BUTTON1 and app is running so killing app process ID $APP_PROCESS_ID"
            kill -9 "$APP_PROCESS_ID"
            echo "Proceeding with app install"
            "$JAMF_BINARY" policy -event "$POLICY_TRIGGER_NAME"
            # Add message it's safe to re-open app
            /bin/launchctl asuser "$USER_ID" /usr/bin/sudo -u "$CURRENT_USER" "$JAMF_HELPER" -windowType utility -windowPosition lr -title "$TITLE2" -description "$DESCRIPTION2" -icon "$AEA11_LOGO" -button1 "$BUTTON1" -defaultButton "1"
            if [ -e "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" ]
            then
                echo "Deferal file exists and needs removed"
                rm -rf "/Library/Application Support/HeartlandAEA11/Reporting/${APP_NAME} Deferral.plist" 
            else
                echo "Deferral file does NOT exist. Skipping plist deletion."
            fi
            exit 0
        fi
    fi
fi


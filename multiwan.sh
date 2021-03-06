#!/usr/bin/env bash

source /etc/multiwan.conf

STARTUP=1
CHECK_INTERVAL=1

# IP address of each WAN interface
WAN_NET1="$(ip addr show $WAN_IF1 | grep "inet " | tr -s [:space:] | cut -d ' ' -f3)"
WAN_NET2="$(ip addr show $WAN_IF2 | grep "inet " | tr -s [:space:] | cut -d ' ' -f3)"

WAN_IP1="$(echo $WAN_NET1 | cut -d '/' -f1)"
WAN_IP2="$(echo $WAN_NET2 | cut -d '/' -f1)"

# Last link status.  Defaults to down to force check of both on first run.
LLS1=1
LLS2=1

# Last ping status.
LPS1=1
LPS2=1

# Current ping status.
CPS1=1
CPS2=1

# Change link status.
CLS1=1
CLS2=1

# Count of consecutive status checks
COUNT1=0
COUNT2=0

function link_status() {
  case $1 in
    0)
      echo "Up" ;;
    1)
      echo "Down" ;;
    *)
      echo "Unknown" ;;
  esac
}

# check_link $IP $TIMEOUT
function check_link() {
  ping -W $2 -I $1 -c 1 $PING_TARGET > /dev/null 2>&1
  RETVAL=$?
  if [ $RETVAL -ne 0 ] ; then
    STATE=1
  else
    STATE=0
  fi

  link_status $STATE

  return $STATE
}

while : ; do
  LINK_STATE="$(check_link $WAN_IP1 $PING_TIMEOUT)"
  CPS1=$?

  if [ $LPS1 -ne $CPS1 ] ; then
    logger -p local6.notice -t MULTIWAN[$$] "Ping state changed for $WAN_TABLE1 from $(link_status $LPS1) to $(link_status $CPS1)"
    COUNT1=1
  else
    if [ $LPS1 -ne $LLS1 ] ; then
      COUNT1=`expr $COUNT1 + 1`
    fi
  fi

  if [[ $COUNT1 -ge $SUCCESS_COUNT || ($LLS1 -eq 0 && $COUNT1 -ge $FAILURE_COUNT) ]]; then
    CLS1=0
    COUNT1=0

    if [ $LLS1 -eq 1 ] ; then
      LLS1=0
    else
      LLS1=1
    fi
    logger -p local6.notice -t MULTIWAN[$$] "Link state for $WAN_TABLE1 is $(link_status $LLS1)"
  else
    CLS1=1
  fi

  LPS1=$CPS1

  LINK_STATE="$(check_link $WAN_IP2 $PING_TIMEOUT)"
  CPS2=$?

  if [ $LPS2 -ne $CPS2 ] ; then
    logger -p local6.notice -t MULTIWAN[$$] "Ping state changed for $WAN_TABLE2 from $(link_status $LPS2) to $(link_status $CPS2)"
    COUNT2=1
  else
    if [ $LPS2 -ne $LLS2 ] ; then
      COUNT2=`expr $COUNT2 + 1`
    fi
  fi

  if [[ $COUNT2 -ge $SUCCESS_COUNT || ($LLS2 -eq 0 && $COUNT2 -ge $FAILURE_COUNT) ]]; then
    CLS2=0
    COUNT2=0

    if [ $LLS2 -eq 1 ]; then
      LLS2=0
    else
      LLS2=1
    fi
    logger -p local6.notice -t MULTIWAN[$$] "Link state for $WAN_TABLE2 is $(link_status $LLS2)"
  else
    CLS2=1
  fi

  LPS2=$CPS2

  if [[ $CLS1 -eq 0 || $CLS2 -eq 0 ]] ; then
    if [[ $STARTUP -eq 1 ]] ; then
      STARTUP=0
      CHECK_INTERVAL=15
    fi
    if [[ $LLS1 -eq 1 && $LLS2 -eq 0 ]] ; then
      logger -p local6.notice -t MULTIWAN[$$] "Applying $WAN_TABLE2 only route."
      ip route change default scope global via $WAN_GW2 dev $WAN_IF2
    elif [[ $LLS1 -eq 0 && $LLS2 -eq 1 ]] ; then
      logger -p local6.notice -t MULTIWAN[$$] "Applying $WAN_TABLE1 only route."
      ip route change default scope global via $WAN_GW1 dev $WAN_IF1
    elif [[ $LLS1 -eq 0 && $LLS2 -eq 0 ]] ; then
      logger -p local6.notice -t MULTIWAN[$$] "Applying multiwan load balancing route."
      ip route replace default scope global nexthop via $WAN_GW1 dev $WAN_IF1 weight $WAN_WEIGHT1 nexthop via $WAN_GW2 dev $WAN_IF2 weight $WAN_WEIGHT2
    fi
  fi

  sleep $CHECK_INTERVAL
done

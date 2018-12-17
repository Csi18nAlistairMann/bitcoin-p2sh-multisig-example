#!/bin/bash
#
# Alistair Mann, 15 December 2018
# 
# This code to implement p2sh-multisig example as worked through at
# https://bitcoin.org/en/developer-examples#p2sh-multisig
#
# This code was used for a Stack Exchange thread of mine at
# https://bitcoin.stackexchange.com/questions/81919
# and includes corrections suggested by
# https://bitcoin.stackexchange.com/users/64730/arubi
#
# The code as stands expects to use testnet, but has a flag for using
# regtest instead.
#
#
echo "[Setting up run ...]"
DEBUG=true
USE_REGTEST=false  # If false, use testnet
ADDRESS_TYPE="p2sh-segwit"
BITCOIND_HOMEDIR="/home/bitcoind"
BITCOIND_CONFDIR=$BITCOIND_HOMEDIR"/.bitcoin"
if [[ "$USE_REGTEST" = "true" ]]
then
    AMOUNT0="49.99900000"
    AMOUNT1="10.00000000"  # Differs from example to forestall float and rounding issues
    AMOUNT2="9.99800000"
    REGTEST_PARAM="-regtest"
    REGTEST_DIR=$BITCOIND_CONFDIR"/regtest"
    BITCOIND_CONFFILE=$BITCOIND_CONFDIR"/regtest.conf"
    TEST_SPEND_FROM_NONCOINBASE=true  # Test if it matters that funds were generational
else
    AMOUNT0="49.99900000"  # Unused on testnet
    AMOUNT1="0.00030001"
    AMOUNT2="0.00015001"
    REGTEST_PARAM=""
    REGTEST_DIR="/dev/null"
    BITCOIND_CONFFILE=$BITCOIND_CONFDIR"/testnet.conf"
    TEST_SPEND_FROM_NONCOINBASE=false
fi
TXFEE="0.00013000"
BITCOIN_CLI="/usr/local/bin/bitcoin-cli -conf="$BITCOIND_CONFFILE" "$REGTEST_PARAM
BITCOIN_DAEMON="/usr/local/bin/bitcoind -conf="$BITCOIND_CONFFILE" "$REGTEST_PARAM" -daemon"
TEST_PUBLIC_KEYS_ONLY=true  # Public keys vs Addresses test

#
# Get regtest network back to a known state: stop if going, unlink regtest folders,
# restart, and generate first 101 blocks to get 50btc in funds. Give a short period
# to allow cleaning up etc. The 101 is important as it limits our balance to 50btc
if [[ "$USE_REGTEST" = "true" ]]
then
    $BITCOIN_CLI stop
    sleep 1
    rm -rf $REGTEST_DIR && $BITCOIN_DAEMON
    sleep 2
    $BITCOIN_CLI generate 101 >/dev/null
fi

#
# I see references such as at https://github.com/bitcoin/bitcoin/issues/7277
# that one cannot send funds from coinbase to p2sh addresses over regtest.
# This code to send almost whole balance over such that a later spend to
# fund p2sh address cannot but come from a non-coinbase address
if [[ "$TEST_SPEND_FROM_NONCOINBASE" = "true" ]]
then
    NONCOINBASE_ADDRESS=`$BITCOIN_CLI getnewaddress $ADDRESS_TYPE`
    TXID=`$BITCOIN_CLI sendtoaddress $NONCOINBASE_ADDRESS $AMOUNT0`
    if $DEBUG
    then
	echo "Sending coinbase funds to new key"
	echo "[NONCOINBASE_ADDRESS]: "$NONCOINBASE_ADDRESS
	echo "[TXID               ]: "$TXID
	echo "-----"
    fi
fi

echo "[...Create and fund a 2-of-3 multisig transaction...]"
#
# Create the addresses we will use
NEW_ADDRESS1=`$BITCOIN_CLI getnewaddress $ADDRESS_TYPE`
NEW_ADDRESS2=`$BITCOIN_CLI getnewaddress $ADDRESS_TYPE`
NEW_ADDRESS3=`$BITCOIN_CLI getnewaddress $ADDRESS_TYPE`
if [[ "$DEBUG" = "true" ]]
then
    # Example says addresses start with m, this code sees them start
    # with 2. Problem?
    echo "Creating new addresses:"
    echo "[NEW_ADDRESS1]: "$NEW_ADDRESS1
    echo "[NEW_ADDRESS2]: "$NEW_ADDRESS2
    echo "[NEW_ADDRESS3]: "$NEW_ADDRESS3
    echo "-----"
fi

#
# Obtain one public key - not sure why. To prove we can
# use either address or public key to create the
# multisigaddress? To show how to obtain the data for
# passing on to others? ("all of which will be converted
# to public keys in the redeem script.")
# NB: validateaddress in example superceded by getaddressinfo
if [[ "$TEST_PUBLIC_KEYS_ONLY" = "true" ]]
then
    RV=`$BITCOIN_CLI getaddressinfo $NEW_ADDRESS1`
    NEW_ADDRESS1_PUBLIC_KEY=`echo $RV | sed 's/^.*"pubkey": "//' | 
    				  sed 's/".*$//'`  # Checked
    RV=`$BITCOIN_CLI getaddressinfo $NEW_ADDRESS2`
    NEW_ADDRESS2_PUBLIC_KEY=`echo $RV | sed 's/^.*"pubkey": "//' | 
    				  sed 's/".*$//'`  # Checked
fi
RV=`$BITCOIN_CLI getaddressinfo $NEW_ADDRESS3`
NEW_ADDRESS3_PUBLIC_KEY=`echo $RV | sed 's/^.*"pubkey": "//' | 
			      sed 's/".*$//'`  # Checked
if [[ "$DEBUG" = "true" ]]
then
    echo "Obtain public key per address:"
    if [[ "$TEST_PUBLIC_KEYS_ONLY" = "true" ]]
    then
	echo "[NEW_ADDRESS1_PUBLIC_KEY]: "$NEW_ADDRESS1_PUBLIC_KEY
	echo "[NEW_ADDRESS2_PUBLIC_KEY]: "$NEW_ADDRESS2_PUBLIC_KEY
    fi
    echo "[NEW_ADDRESS3_PUBLIC_KEY]: "$NEW_ADDRESS3_PUBLIC_KEY
    echo "-----"
fi

#
# Obtain the address and redeem script needed to obtain the funds.
# NB: createmultisig in example superceded by addmultisigaddress
if [[ "$TEST_PUBLIC_KEYS_ONLY" = "true" ]]
then
    RV=`$BITCOIN_CLI addmultisigaddress 2 '''
      [
       "'$NEW_ADDRESS1_PUBLIC_KEY'",
       "'$NEW_ADDRESS2_PUBLIC_KEY'", 
       "'$NEW_ADDRESS3_PUBLIC_KEY'"
      ]'''`
else
    RV=`$BITCOIN_CLI addmultisigaddress 2 '''
    [
      "'$NEW_ADDRESS1'",
      "'$NEW_ADDRESS2'", 
      "'$NEW_ADDRESS3_PUBLIC_KEY'"
    ]'''`
fi
P2SH_ADDRESS=`echo $RV | sed 's/^.*"address": "//' | 
		   sed 's/".*$//'`  # Checked
P2SH_REDEEM_SCRIPT=`echo $RV | sed 's/^.*"redeemScript": "//' | 
			 sed 's/".*$//'`  # Checked
if [[ "$DEBUG" = "true" ]]
then
    echo "Obtain p2sh address and redeemScript:"
    echo "[P2SH_ADDRESS      ]: "$P2SH_ADDRESS
    echo "[P2SH_REDEEM_SCRIPT]: "$P2SH_REDEEM_SCRIPT
    echo "-----"
fi

#
# On regtest, send funds from the first 50btc block we can spend
# to the p2sh_address determined above.
# On testnet, send part of our balance
if [[ "$USE_REGTEST" != "true" ]]
then
    RV=`$BITCOIN_CLI settxfee $TXFEE`
fi
UTXO_TXID=`$BITCOIN_CLI sendtoaddress $P2SH_ADDRESS $AMOUNT1`
if [[ "$DEBUG" = "true" ]]
then
    echo "Fund p2sh address"
    echo "[UTXO_TXID]: "$UTXO_TXID
    echo "-----"
fi

#
# Get everything thus far into a block
# $BITCOIN_CLI generate 1 >/dev/null

#
#

echo "[...Redeem the 2-of-3 transaction]"
#
# Obtain details about the funded transaction. We want whichever output
# was the 10btc output even though the example suggests there is only
# one output.
# NB: second parameter in example superceded after v0.14.0
RV=`$BITCOIN_CLI getrawtransaction $UTXO_TXID true`
UTXO2_VALUE=`echo $RV | sed 's/^.*"value": //' | sed 's/,.*$//'`  # Checked
UTXO2_VOUT=`echo $RV | sed 's/^.*"n": //' | sed 's/,.*$//'`  # Checked
UTXO2_OUTPUT_SCRIPT=`echo $RV | sed 's/^.*"scriptPubKey"//' | sed 's/"reqSigs".*$//' | 
			  sed 's/^.*"hex": "//' | sed 's/".*$//'`  # Checked
UTXO1_VALUE=`echo $RV | sed 's/"addresses":.*//' | sed 's/^.*"value": //' | 
		  sed 's/,.*$//'`  # Checked
UTXO1_VOUT=`echo $RV | sed 's/"addresses":.*//' | sed 's/^.*"n": //' | 
		 sed 's/,.*$//'`  # Checked
UTXO1_OUTPUT_SCRIPT=`echo $RV | sed 's/"addresses":.*//' | sed 's/^.*"scriptPubKey"//' | 
			  sed 's/"reqSigs".*$//' | sed 's/^.*"hex": "//' | 
			  sed 's/".*$//'`  # Checked
if [[ "$UTXO1_VALUE" = "$AMOUNT1" ]]
then
    # Use first output (change is the second output)
    UTXO_VOUT=$UTXO1_VOUT
    UTXO_OUTPUT_SCRIPT=$UTXO1_OUTPUT_SCRIPT
else
    # Use second output (changes was the first output)
    UTXO_VOUT=$UTXO2_VOUT
    UTXO_OUTPUT_SCRIPT=$UTXO2_OUTPUT_SCRIPT
fi
if [[ "$DEBUG" = "true" ]]
then
    echo "Capture which outputs we'll use:"
    echo "[1 VALUE            ]: "$UTXO1_VALUE
    echo "[1 VOUT             ]: "$UTXO1_VOUT
    echo "[1 OUTPUT_SCRIPT    ]: "$UTXO1_OUTPUT_SCRIPT
    echo "[2 VALUE            ]: "$UTXO2_VALUE
    echo "[2 VOUT             ]: "$UTXO2_VOUT
    echo "[2 OUTPUT_SCRIPT    ]: "$UTXO2_OUTPUT_SCRIPT
    echo "Vout and Output script chosen:"
    echo "[UTXO_VOUT          ]: "$UTXO_VOUT
    echo "[UTXO_OUTPUT_SCRIPT ]: "$UTXO_OUTPUT_SCRIPT
    echo "-----"
fi

#
# Now create the address redeemed to
NEW_ADDRESS4=`$BITCOIN_CLI getnewaddress $ADDRESS_TYPE`
if [[ "$DEBUG" = "true" ]]
then
    echo "Create redeem-to address:"
    echo "[NEW_ADDRESS4]: "$NEW_ADDRESS4
    echo "-----"
fi

# Also note https://github.com/Csi18nAlistairMann/bitcoin-p2sh-multisig-example/issues/1
# where @bitcoinmonkey suggests using fundrawtransaction() in the code beneath. 
#
# Create a new transaction, slightly less value to accomodate mining fee
RAW_TX=`$BITCOIN_CLI createrawtransaction '''
   [
      {
        "txid": "'$UTXO_TXID'",
        "vout": '$UTXO_VOUT'
      }
   ]
   ''' '''
   {
     "'$NEW_ADDRESS4'": '$AMOUNT2'
   }'''`
RAW_TX_SZ=${#RAW_TX}
if [[ "$DEBUG" = "true" ]]
then
    echo "Generate unsigned transaction:"
    echo "[RAW_TX]: "$RAW_TX
    echo "-----"
fi

#
# Get 2 of the 3 private keys
NEW_ADDRESS1_PRIVATE_KEY=`$BITCOIN_CLI dumpprivkey $NEW_ADDRESS1`
NEW_ADDRESS3_PRIVATE_KEY=`$BITCOIN_CLI dumpprivkey $NEW_ADDRESS3`
if [[ "$DEBUG" = "true" ]]
then
    echo "Capture private keys for use in signing:"
    echo "[NEW_ADDRESS1_PRIVATE_KEY]: "$NEW_ADDRESS1_PRIVATE_KEY
    echo "[NEW_ADDRESS3_PRIVATE_KEY]: "$NEW_ADDRESS3_PRIVATE_KEY
    echo "-----"
fi

#
# 1 of 3 sign off the transaction
# NB: signrawtransaction in example superceded by signrawtransactionwithkey
# NB: order of parameters reverse, and amount becomes mandatory
RV=`$BITCOIN_CLI signrawtransactionwithkey $RAW_TX '''
    [
      "'$NEW_ADDRESS1_PRIVATE_KEY'"
    ]
    ''' '''
    [
      {
        "txid": "'$UTXO_TXID'", 
        "vout": '$UTXO_VOUT', 
        "scriptPubKey": "'$UTXO_OUTPUT_SCRIPT'", 
        "redeemScript": "'$P2SH_REDEEM_SCRIPT'",
	"amount": '$AMOUNT1'
      }
    ]'''`
PARTLY_SIGNED_RAW_TX=`echo $RV | sed 's/^.*"hex": "//' | sed 's/".*//'`
PARTLY_SIGNED_RAW_TX_SZ=${#PARTLY_SIGNED_RAW_TX}
if [[ $PARTLY_SIGNED_RAW_TX_SZ -eq $RAW_TX_SZ ]]
then
    echo "Transaction didn't change size at PARTLY_SIGNED_RAW_TX_SZ. Eh?"
    exit
fi
if [[ $PARTLY_SIGNED_RAW_TX_SZ -eq 0 ]]
then
    echo "Failed at PARTLY_SIGNED_RAW_TX"
    echo "Response: "
    echo "[RAW_TX                  ]: "$RAW_TX
    echo "[UTXO_TXID               ]: "$UTXO_TXID
    echo "[UTXO_VOUT               ]: "$UTXO_VOUT
    echo "[UTXO_OUTPUT_SCRIPT      ]: "$UTXO_OUTPUT_SCRIPT
    echo "[P2SH_REDEEM_SCRIPT      ]: "$P2SH_REDEEM_SCRIPT
    echo "[NEW_ADDRESS1_PRIVATE_KEY]: "$NEW_ADDRESS1_PRIVATE_KEY
    exit
fi
if [[ "$DEBUG" = "true" ]]
then
    echo "Transaction after first signature:"
    echo "[PARTLY_SIGNED_RAW_TX    ]: "$PARTLY_SIGNED_RAW_TX
    echo "-----"
fi

#
# 2 of 3 signs off the transaction
RV=`$BITCOIN_CLI signrawtransactionwithkey $PARTLY_SIGNED_RAW_TX '''
    [
      "'$NEW_ADDRESS3_PRIVATE_KEY'"
    ]
    ''' '''
    [
      {
        "txid": "'$UTXO_TXID'", 
        "vout": '$UTXO_VOUT', 
        "scriptPubKey": "'$UTXO_OUTPUT_SCRIPT'", 
        "redeemScript": "'$P2SH_REDEEM_SCRIPT'",
	"amount": '$AMOUNT1'
      }
    ]'''`
SIGNED_RAW_TX=`echo $RV | sed 's/^.*"hex": "//' | sed 's/".*//'`  # Checked
SIGNED_RAW_TX_SZ=${#SIGNED_RAW_TX}
COMPLETE=`echo $RV | sed 's/^.*"complete": //' | sed 's/\W.*//'`  # Checked
if [[ "$COMPLETE" != "true" ]]
then
    echo "Second signature did not lead to completed transaction. Eh?"
    echo $RV
    exit
fi
if [[ "$DEBUG" = "true" ]]
then
    echo "Transaction after second signature:" 
    echo "[SIGNED_RAW_TX]: "$SIGNED_RAW_TX
    echo "-----"
fi

#
# And now broadcast it
TXID=`$BITCOIN_CLI sendrawtransaction $SIGNED_RAW_TX`
if [[ ${#TXID} -eq 0 ]]
then
    echo "Broadcast has gone wrong. Eh?"
fi
if [[ "$DEBUG" = "true" ]]
then
    echo "TXID from broadcasting:"
    echo "[TXID]: "$TXID
    echo "-----"
fi

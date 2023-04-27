{-# LANGUAGE DataKinds          #-}
{-# LANGUAGE FlexibleInstances  #-}
{-# LANGUAGE NoImplicitPrelude  #-}
{-# LANGUAGE NumericUnderscores #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module PTEscrowNFT where

import qualified EscrowNFT       as OnChain
import           Control.Monad           (mapM, replicateM)
import           Data.String             (fromString)
import           Plutus.Model            (Ada (Lovelace), DatumMode (HashDatum, InlineDatum),
                                          Run, Tx,
                                          TypedValidator (TypedValidator),
                                          UserSpend, FakeCoin (..), fakeCoin, fakeValue, ada, adaValue,
                                          defaultBabbage, initMock, mustFail,
                                          newUser, payToKey, payToScript,
                                          runMock, spend, spendScript, submitTx,
                                          toV2, userSpend, utxoAt, valueAt, waitUntil, currentTimeRad, validateIn)
import           Plutus.V2.Ledger.Api    (PubKeyHash, TokenName, TxOut (txOutValue),
                                          TxOutRef, Value, POSIXTime (POSIXTime, getPOSIXTime))
import           PlutusTx.Builtins       (Integer, BuiltinByteString, encodeUtf8, mkI)
import           PlutusTx.Prelude        (Bool (..), Eq ((==)),
                                          return, ($), (&&), (.))
import           Prelude                 (IO, String, Ord ((<), (>)),
                                          mconcat)
import           Test.QuickCheck         (Property, Testable (property),
                                          collect, (==>), Arbitrary (arbitrary), choose)
import           Test.QuickCheck.Monadic (assert, monadic, run)
import           Test.Tasty              (defaultMain, testGroup)
import           Test.Tasty.QuickCheck   as QC (testProperty)


-- | Helper functions for using Quickcheck
-- | Testable and Arbitrary instances to generate random cases for the validators parameters 

-- | 100_000_000 goes to the administrator of the mockup blockchain, which then sends to the demo users setup later in the code.
instance Testable a => Testable (Run a) where
  property rp = let (a,_) = runMock rp $ initMock defaultBabbage (adaValue 100_000_000) in property a


-- | Our on chain validator checks 3 things
-- 1. A matching password
-- 2. A matching TokenName
-- 3. If the user is burning the NFT when unlocking the funds 
-- We will use the FakeCoin, fakecoin, fakevalue functions from Plutus.Model.Mint


-- | Validator's script
-- | Versioning the validator to v2

valScript :: TypedValidator datum redeemer
valScript = TypedValidator $ toV2 OnChain.typedValidator

-- Set many users at once
twoDemoUsers :: Run [PubKeyHash]
twoDemoUsers = replicateM 2 $ newUser $ ada (Lovelace 10000000)

toBBString :: String -> PlutusTx.Builtins.BuiltinByteString
toBBString = PlutusTx.Builtins.encodeUtf8 . fromString


nftToken = FakeCoin {
    fakeCoin'tag = toBBString "LockDaFund"
}

nftTokenValue :: Value
nftTokenValue = fakeValue nftToken 1



------------------------------------------------------------------------------------
-------------------------- MONOIDAL TX For SUbmission ------------------------------

-- Create transaction that spends "usp" to lock "vl" in "escrowScript"
-- | "usp" is basically the users utxos that will be used as inputs in the transaction to be consumed for locking funds to script.
-- | For a new utxo to come, another has to die.
lockFunds2Script :: PubKeyHash -> Integer -> TokenName -> Integer -> UserSpend -> Value -> Tx
lockFunds2Script ph amt tn pwd usp vl =
  mconcat
    [ userSpend usp
    , payToScript valScript (InlineDatum (OnChain.EscrowDatum ph amt tn pwd)) vl
    ]
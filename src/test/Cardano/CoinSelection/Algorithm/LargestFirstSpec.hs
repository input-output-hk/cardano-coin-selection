{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Cardano.CoinSelection.Algorithm.LargestFirstSpec
    ( spec
    ) where

import Prelude

import Cardano.CoinSelection
    ( CoinMap (..)
    , CoinMapEntry (..)
    , CoinSelection (..)
    , CoinSelectionAlgorithm (..)
    , CoinSelectionError (..)
    , CoinSelectionLimit (..)
    , CoinSelectionParameters (..)
    , CoinSelectionResult (..)
    , InputLimitExceededError (..)
    , InputValueInsufficientError (..)
    , coinMapToList
    )
import Cardano.CoinSelection.Algorithm.LargestFirst
    ( largestFirst )
import Cardano.CoinSelectionSpec
    ( CoinSelProp (..)
    , CoinSelectionFixture (..)
    , CoinSelectionTestResult (..)
    , coinSelectionUnitTest
    )
import Cardano.Test.Utilities
    ( Address, TxIn, excluding, unsafeCoin )
import Control.Monad
    ( unless )
import Control.Monad.Trans.Except
    ( runExceptT )
import Data.Either
    ( isRight )
import Data.Functor.Identity
    ( Identity (runIdentity) )
import Test.Hspec
    ( Spec, describe, it, shouldSatisfy )
import Test.QuickCheck
    ( Property, property, (==>) )

import qualified Data.List as L
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

spec :: Spec
spec = do
    describe "Coin selection: largest-first algorithm: unit tests" $ do

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionTestResult
                { rsInputs = [17]
                , rsChange = []
                , rsOutputs = [17]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [10,10,17]
                , txOutputs = [17]
                })

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionTestResult
                { rsInputs = [17]
                , rsChange = [16]
                , rsOutputs = [1]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [12,10,17]
                , txOutputs = [1]
                })

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionTestResult
                { rsInputs = [12, 17]
                , rsChange = [11]
                , rsOutputs = [18]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [12,10,17]
                , txOutputs = [18]
                })

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionTestResult
                { rsInputs = [10, 12, 17]
                , rsChange = [9]
                , rsOutputs = [30]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [12,10,17]
                , txOutputs = [30]
                })

        coinSelectionUnitTest largestFirst ""
            (Right $ CoinSelectionTestResult
                { rsInputs = [6,10]
                , rsChange = [4]
                , rsOutputs = [11,1]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 3
                , utxoInputs = [1,2,10,6,5]
                , txOutputs = [11, 1]
                })

        coinSelectionUnitTest largestFirst
            "UTxO balance not sufficient"
            (Left $ InputValueInsufficient $ InputValueInsufficientError
                (unsafeCoin @Int 39) (unsafeCoin @Int 40))
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [12,10,17]
                , txOutputs = [40]
                })

        coinSelectionUnitTest largestFirst
            "UTxO balance not sufficient"
            (Left $ InputValueInsufficient $ InputValueInsufficientError
                (unsafeCoin @Int 39) (unsafeCoin @Int 43))
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [12,10,17]
                , txOutputs = [40,1,1,1]
                })

        coinSelectionUnitTest largestFirst
            "UTxO balance sufficient"
            (Right $ CoinSelectionTestResult
                { rsInputs = [12,17,20]
                , rsChange = [6]
                , rsOutputs = [1,1,1,40]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [12,20,17]
                , txOutputs = [40,1,1,1]
                })

        coinSelectionUnitTest largestFirst
            "UTxO balance sufficient"
            (Right $ CoinSelectionTestResult
                { rsInputs = [12,17,20]
                , rsChange = [8]
                , rsOutputs = [1,40]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [12,20,17]
                , txOutputs = [40, 1]
                })

        coinSelectionUnitTest largestFirst
            "UTxO balance sufficient"
            (Right $ CoinSelectionTestResult
                { rsInputs = [10,20,20]
                , rsChange = [3]
                , rsOutputs = [6,41]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 100
                , utxoInputs = [20,20,10,5]
                , txOutputs = [41, 6]
                })

        coinSelectionUnitTest largestFirst
            "UTxO balance sufficient, but maximum input count exceeded"
            (Left $ InputLimitExceeded $ InputLimitExceededError 9)
            (CoinSelectionFixture
                { maxNumOfInputs = 9
                , utxoInputs = replicate 100 1
                , txOutputs = replicate 100 1
                })

        coinSelectionUnitTest largestFirst
            "UTxO balance sufficient, but maximum input count exceeded"
            (Left $ InputLimitExceeded $ InputLimitExceededError 9)
            (CoinSelectionFixture
                { maxNumOfInputs = 9
                , utxoInputs = replicate 100 1
                , txOutputs = replicate 10 10
                })

        coinSelectionUnitTest largestFirst
            "UTxO balance sufficient"
            (Right $ CoinSelectionTestResult
                { rsInputs = [6,10]
                , rsChange = [4]
                , rsOutputs = [1,11]
                })
            (CoinSelectionFixture
                { maxNumOfInputs = 2
                , utxoInputs = [1,2,10,6,5]
                , txOutputs = [11, 1]
                })

    describe "Coin selection: largest-first algorithm: properties" $ do

        it "forall (UTxO, NonEmpty TxOut), for all selected input, there's no \
            \bigger input in the UTxO that is not already in the selected \
            \inputs"
            (property $ propInputDecreasingOrder @TxIn @Address)

--------------------------------------------------------------------------------
-- Properties
--------------------------------------------------------------------------------

propInputDecreasingOrder
    :: Ord i
    => CoinSelProp i o
    -> Property
propInputDecreasingOrder (CoinSelProp utxo txOuts) =
    isRight selection ==>
        let Right (CoinSelectionResult s _) = selection in
        prop s
  where
    prop (CoinSelection inps _ _) =
        let
            utxo' = (Map.toList . unCoinMap) $ utxo `excluding`
                Set.fromList (entryKey <$> coinMapToList inps)
        in unless (L.null utxo') $
            (L.minimum (entryValue <$> coinMapToList inps))
            `shouldSatisfy`
            (>= (L.maximum (snd <$> utxo')))
    selection = runIdentity
        $ runExceptT
        $ selectCoins largestFirst
        $ CoinSelectionParameters utxo txOuts selectionLimit
    selectionLimit = CoinSelectionLimit $ const 100

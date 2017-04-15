{-# OPTIONS_GHC -fno-warn-name-shadowing #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}
module Clr.CSharp.Inline (csharp, csharp') where

import           Clr.Inline.Config
import           Clr.Inline.Quoter
import           Clr.Inline.Utils
import           Clr.Inline.Utils.Embed
import           Clr.Inline.Types
import           Control.Monad
import           Control.Monad.Trans.Writer
import qualified Data.ByteString            as BS
import           Data.List
import qualified Data.Map as Map
import           Language.Haskell.TH
import           Language.Haskell.TH.Quote
import           System.Directory
import           System.FilePath            ((<.>), (</>))
import           System.IO.Temp
import           System.Process
import           Text.Printf

-- | Quasiquoter for C# declarations and expressions.
--   A quasiquote is a block of C# statements wrapped in curly braces
--   preceded by the C# return type.
--   Examples:
--
-- @
-- example :: IO (Object "int[]")
-- example = do
--  [csharp| Console.WriteLine("Hello CLR inline !!!"); |]
--  i <- [csharp| int { return 2; }|]
--  [csharp| int[] {  int[] a = new int[4]{0,0,0,0};
--                    for(int i=0; i < 4; i++) {
--                      a[i] = i;
--                    }
--                    return a;
--                 }|]
-- @
--
--   See the documentation for 'fsharp' for details on the quotation
--   and antiquotation syntaxes.
--  This quasiquoter is implicitly configured with the 'defaultConfig'.
csharp :: QuasiQuoter
csharp = csharp' defaultConfig

name :: String
name = "csharp"

-- | Explicit configuration version of 'csharp'.
csharp' :: ClrInlineConfig -> QuasiQuoter
csharp' cfg = QuasiQuoter
    { quoteExp  = csharpExp cfg
    , quotePat  = error "Clr.CSharp.Inline: quotePat"
    , quoteType = error "Clr.CSharp.Inline: quoteType"
    , quoteDec  = csharpDec cfg
    }

csharpExp :: ClrInlineConfig -> String -> Q Exp
csharpExp cfg =
  clrQuoteExp
    name
    (compile cfg)
csharpDec :: ClrInlineConfig -> String -> Q [Dec]
csharpDec cfg = clrQuoteDec name $ compile cfg

data CSharp

genCode :: ClrInlinedGroup CSharp -> String
genCode ClrInlinedGroup {..} =
  unlines $
  execWriter $ do
    yield $ printf "namespace %s {" modNamespace
    forM_ units $ \case
      ClrInlinedDec body ->
        yield body
      ClrInlinedExp{} ->
        return ()
    yield $ printf "public class %s {" modName
    forM_ units $ \case
      ClrInlinedDec{} ->
        return ()
      ClrInlinedExp ClrInlinedExpDetails {..} -> do
        yield $
          printf
            "    public static %s %s (%s) { "
            returnType
            (getMethodName name unitId)
            (intercalate ", " [printf "%s %s" t a | (a, ClrType t) <- Map.toList args])
        forM_ (lines body) $ \l -> yield $ printf "        %s" l
        yield "}"
    yield "}}"

compile :: ClrInlineConfig -> ClrInlinedGroup CSharp -> IO ClrBytecode
compile ClrInlineConfig{..} m@ClrInlinedGroup {..} = do
    temp <- getTemporaryDirectory
    dir <- createTempDirectory temp "inline-csharp"
    let src = dir </> modName <.> ".cs"
        tgt = dir </> modName <.> ".dll"
    writeFile src (genCode m)
    callCommand $
      unwords $
      execWriter $ do
        yield configCSharpPath
        yield "-target:library"
        yield $ "-out:" ++ tgt
        when configDebugSymbols $ yield "-debug"
        forM_ configExtraIncludeDirs $ \dir -> yield $ "-lib:" ++ dir
        forM_ configDependencies $ \name -> yield $ "-reference:" ++ name
        yieldAll configCustomCompilerFlags
        yield src
    bcode <- BS.readFile tgt
    return $ ClrBytecode bcode

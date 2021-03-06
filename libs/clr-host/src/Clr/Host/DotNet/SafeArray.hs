module Clr.Host.DotNet.SafeArray where

import Clr.Host.DotNet.Common
import Clr.Host.DotNet.Variant
import Data.Int
import Data.Word
import Foreign.Ptr

newtype SafeArray = SafeArray (Ptr ()) deriving (Show, Eq)

foreign import stdcall "SafeArrayCreateVector" prim_SafeArrayCreateVector :: VarType -> Int32 -> Word32 -> IO SafeArray
foreign import stdcall "SafeArrayAccessData"   prim_SafeArrayAccessData   :: SafeArray -> Ptr (Ptr a) -> IO HResult
foreign import stdcall "SafeArrayUnaccessData" prim_SafeArrayUnaccessData :: SafeArray -> IO HResult
foreign import stdcall "SafeArrayDestroy"      prim_SafeArrayDestroy      :: SafeArray -> IO HResult


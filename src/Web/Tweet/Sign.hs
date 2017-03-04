{-# LANGUAGE OverloadedStrings #-}

-- | Functions to sign HTTP requests with oAuth
module Web.Tweet.Sign where

import Web.Tweet.Utils
import Web.Authenticate.OAuth
import Network.HTTP.Client

-- | Sign a request using your OAuth dev token.
-- Uses the IO monad because signatures require a timestamp
signRequest :: FilePath -> Request -> IO Request
signRequest filepath req = do
    o <- oAuth filepath
    c <- credential filepath
    signOAuth o c req

-- | Create an OAuth from config data in a file
oAuth :: FilePath -> IO OAuth
oAuth filepath = do
    secret <- (lineByKey "api-sec") <$> getConfigData filepath
    key <- (lineByKey "api-key") <$> getConfigData filepath
    let url = "api.twitter.com"
    return newOAuth { oauthConsumerKey = key , oauthConsumerSecret = secret , oauthServerName = url }

-- | Create a new credential from a token and token secret
credential :: FilePath -> IO Credential
credential filepath = newCredential <$> token <*> secretToken
    where token       = (lineByKey "tok") <$> getConfigData filepath
          secretToken = (lineByKey "tok-sec") <$> getConfigData filepath
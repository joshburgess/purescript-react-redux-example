module Example.App (main) where

import Prelude

import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (CONSOLE, info)
import Control.Monad.Eff.Timer (TIMER, setTimeout)
import Control.Monad.Eff.Unsafe (unsafeCoerceEff)

import Data.Maybe (Maybe(..), maybe)
import Data.Newtype (wrap)

import React as React
import React.DOM as DOM
import React.DOM.Props as Props

import React.Redux
  ( BaseDispatch
  , ConnectClass'
  , Reducer
  , ReduxEffect
  , ReduxStore
  , ReduxStoreEnhancer
  , applyMiddleware
  , connect_
  , createElement_
  , createProviderElement
  , createStore
  ) as Redux

type State = { counterA :: Int, counterB :: Int }

data Action = ActionA ActionA | ActionB ActionB

data ActionA = IncrementA | DelayedIncrementA Int

data ActionB = IncrementB

type Effect eff = (console :: CONSOLE, timer :: TIMER | eff)

store :: forall eff. Eff (Effect (Redux.ReduxEffect eff)) (Redux.ReduxStore (Effect eff) State Action)
store = Redux.createStore reducer initialState (middlewareEnhancer <<< reduxDevtoolsExtensionEnhancer)
  where
  initialState :: State
  initialState = { counterA: 0, counterB: 0 }

  middlewareEnhancer :: Redux.ReduxStoreEnhancer (Effect eff) State Action
  middlewareEnhancer = Redux.applyMiddleware (wrap <$> [ loggerMiddleware, timeoutSchedulerMiddleware ])
    where
    loggerMiddleware { getState, dispatch } next action = do
      _ <- info (showAction action)
      _ <- next action
      state <- getState
      logState state
      where
      logState :: State -> Eff (Effect (Redux.ReduxEffect eff)) Unit
      logState { counterA, counterB } = info ("state = { counterA: " <> show counterA <> ", " <> "counterB: " <> show counterB <> " }")

      showAction :: Action -> String
      showAction =
        case _ of
             ActionA IncrementA -> "ActionA IncremementA"
             ActionA (DelayedIncrementA delay) -> "ActionA (DelayedIncrementA " <> show delay <> ")"
             ActionB IncrementB -> "ActionB IncremementB"

    timeoutSchedulerMiddleware { getState, dispatch } next action =
      case action of
           ActionA (DelayedIncrementA delay) -> void (setTimeout delay (void (next action)))
           _ -> void (next action)

  reducer :: Redux.Reducer Action State
  reducer =
    wrap reducerA <<<
    wrap reducerB
    where
    reducerA action state =
      case action of
           ActionA IncrementA -> state { counterA = state.counterA + 1 }
           ActionA (DelayedIncrementA _) -> state { counterA = state.counterA + 1 }
           _ -> state

    reducerB action state =
      case action of
           ActionB IncrementB -> state { counterB = state.counterB + 1 }
           _ -> state

type IncrementAProps eff
  = { a :: Int
    , onIncrement :: Maybe Int -> Eff eff Unit
    }

incrementAClass :: forall eff. React.ReactClass (IncrementAProps eff)
incrementAClass = React.createClassStateless render
  where
  render :: IncrementAProps eff -> React.ReactElement
  render { a
         , onIncrement
         } =
    DOM.div []
      [ DOM.button
          [ Props.onClick (\event -> unsafeCoerceEff (onIncrement Nothing)) ]
          [ DOM.text ("Increment A: " <> show a) ]
      , DOM.button
          [ Props.onClick (const $ unsafeCoerceEff (onIncrement (Just 2000))) ]
          [ DOM.text ("Increment A (delayed by 2s): " <> show a) ]
      ]

type IncrementBProps eff
  = { b :: Int
    , onIncrement :: Eff eff Unit
    }

incrementBClass :: forall eff. React.ReactClass (IncrementBProps eff)
incrementBClass = React.createClassStateless render
  where
  render :: IncrementBProps eff -> React.ReactElement
  render { b
         , onIncrement
         } =
    DOM.div []
      [ DOM.button
          [ Props.onClick (const $ unsafeCoerceEff onIncrement) ]
          [ DOM.text ("Increment B: " <> show b) ]
      ]

incrementAComponent :: forall eff. Redux.ConnectClass' State (IncrementAProps eff) Action
incrementAComponent = Redux.connect_ stateToProps dispatchToProps { } incrementAClass
  where
  stateToProps :: State -> { a :: Int }
  stateToProps { counterA } =
    { a: counterA
    }

  dispatchToProps :: Redux.BaseDispatch eff Action -> { onIncrement :: Maybe Int -> Eff eff Unit }
  dispatchToProps dispatch =
    { onIncrement: void <<< unsafeCoerceEff <<< dispatch <<< ActionA <<< maybe IncrementA DelayedIncrementA
    }

incrementBComponent :: forall eff. Redux.ConnectClass' State (IncrementBProps eff) Action
incrementBComponent = Redux.connect_ stateToProps dispatchToProps { withRef: true } incrementBClass
  where
  stateToProps { counterB } =
    { b: counterB
    }

  dispatchToProps dispatch =
    { onIncrement: void (unsafeCoerceEff (dispatch (ActionB IncrementB)))
    }

type AppProps = Unit

appClass :: React.ReactClass AppProps
appClass = React.createClass (React.spec unit render)
  where
  render :: forall eff. React.Render AppProps Unit eff
  render this = render' <$> React.getProps this
    where
    render' :: AppProps -> React.ReactElement
    render' _ =
      DOM.div []
              [ Redux.createElement_ incrementAComponent []
              , Redux.createElement_ incrementBComponent []
              ]

main :: forall eff. Eff (Effect (Redux.ReduxEffect eff)) React.ReactElement
main = do
  store' <- store

  let element = Redux.createProviderElement store' [ React.createElement appClass unit [] ]

  pure element

foreign import reduxDevtoolsExtensionEnhancer :: forall eff state action. Redux.ReduxStoreEnhancer eff state action

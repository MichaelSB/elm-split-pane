module SplitPane
    exposing
        ( view
        , ViewConfig
        , createViewConfig
        , createCustomSplitter
        , CustomSplitter
        , HtmlDetails
        , State
        , Msg(..)
        , Orientation(..)
        , SizeUnit(..)
        , subscriptions
        , update
        , customUpdate
        , UpdateConfig
        , createUpdateConfig
        , init
        , configureSplitter
        , orientation
        , draggable
        , percentage
        , px
        , MousePosition
        )

{-|

This is a split pane view library. Can be used to split views into multiple parts with a splitter between them.

Check out the [examples][] to see how it works.

[examples]: https://github.com/doodledood/elm-split-pane/tree/master/examples

# View

@docs view, createViewConfig

# Update

@docs update, subscriptions

# State

@docs State, init, configureSplitter, orientation, draggable

# Helpers

@docs percentage, px

# Definitions

@docs Msg, Orientation, SizeUnit, ViewConfig, UpdateConfig, CustomSplitter, HtmlDetails

# Customization

@docs customUpdate, createUpdateConfig, createCustomSplitter
-}

import Html exposing (Html, span, div, Attribute)
import Html.Attributes exposing (class, style)
import Html.Events exposing (custom)
import Browser.Events as BEvents
import Json.Decode as Json exposing (field, at)
import Json.Decode.Pipeline exposing (required)

import Bound
    exposing
        ( Bounded
        , getValue
        , updateValue
        , createBound
        , createBounded
        )


-- MODEL


{-| Size unit for setting slider - either percentage value between 0.0 and 1.0 or pixel value (> 0)
-}
type SizeUnit
    = Percentage (Bounded Float)
    | Px (Bounded Int)


{-| Orientation of pane.
-}
type Orientation
    = Horizontal
    | Vertical


{-| Keeps dimensions of pane.
-}
type alias PaneDOMInfo =
    { width : Int
    , height : Int
    }


{-| Keep relevant information for the drag operations.
-}
type alias DragInfo =
    { paneInfo : PaneDOMInfo
    , anchor : Position
    }


{-| Drag state information.
-}
type DragState
    = Draggable (Maybe DragInfo)
    | NotDraggable


{-| Tracks state of pane.
-}
type State
    = State
        { orientation : Orientation
        , splitterPosition : SizeUnit
        , dragState : DragState
        }


{-| Internal messages.
-}
type Msg
    = SplitterClick DOMInfo
    | SplitterMove MousePosition
    | SplitterLeftAlone MousePosition


{-| Describes a mouse/touch position
-}
type alias Position =
    { x : Int
    , y : Int
    }

type alias MousePosition =
    { clientX : Int
    , clientY : Int
    , pageX : Int
    , pageY : Int
    , screenX : Int
    , screenY : Int
    , offsetX : Int
    , offsetY : Int
    }

{-| Sets whether the pane is draggable or not
-}
draggable : Bool -> State -> State
draggable isDraggable (State state) =
    State
        { state
            | dragState =
                if isDraggable then
                    Draggable Nothing
                else
                    NotDraggable
        }


{-| Changes orientation of the pane.
-}
orientation : Orientation -> State -> State
orientation o (State state) =
    State { state | orientation = o }


{-| Change the splitter position and limit
-}
configureSplitter : SizeUnit -> State -> State
configureSplitter newPosition (State state) =
    State
        { state
            | splitterPosition = newPosition
        }


{-| Creates a percentage size unit from a float
-}
percentage : Float -> Maybe ( Float, Float ) -> SizeUnit
percentage x bound =
    let
        newBound =
            case bound of
                Just ( lower, upper ) ->
                    createBound lower upper

                Nothing ->
                    createBound 0.0 1.0
    in
        Percentage <| createBounded x newBound


{-| Creates a pixel size unit from an int
-}
px : Int -> Maybe ( Int, Int ) -> SizeUnit
px x bound =
    let
        newBound =
            case bound of
                Just ( lower, upper ) ->
                    createBound lower upper

                Nothing ->
                    createBound 0 9999999999
    in
        Px <| createBounded x newBound



-- INIT


{-| Initialize a new model.

        init Horizontal
-}
init : Orientation -> State
init o =
    State
        { orientation = o
        , splitterPosition = percentage 0.5 Nothing
        , dragState = Draggable Nothing
        }



-- UPDATE


domInfoToPosition : DOMInfo -> Position
domInfoToPosition { x, y, touchX, touchY } =
    case ( (x, y), (touchX, touchY) ) of
        ( (_, _), (Just posX, Just posY) ) ->
            { x = posX, y = posY }

        ( (Just posX, Just posY), (_, _) ) ->
            { x = posX, y = posY }

        _ ->
            { x = 0, y = 0 }


{-| Configuration for updates.
-}
type UpdateConfig msg
    = UpdateConfig
        { onResize : SizeUnit -> Maybe msg
        , onResizeStarted : Maybe msg
        , onResizeEnded : Maybe msg
        }


{-| Creates the update configuration.
    Gives you the option to respond to various things that happen.

    For example:
    - Draw a different view when the pane is resized:

        updateConfig
            { onResize (\p -> Just (SwitchViews p))
            , onResizeStarted Nothing
            , onResizeEnded Nothing
            }
-}
createUpdateConfig :
    { onResize : SizeUnit -> Maybe msg
    , onResizeStarted : Maybe msg
    , onResizeEnded : Maybe msg
    }
    -> UpdateConfig msg
createUpdateConfig config =
    UpdateConfig config


{-| Updates internal model.
-}
update : Msg -> State -> State
update msg model =
    let
        ( updatedModel, _ ) =
            customUpdate
                (createUpdateConfig
                    { onResize = \_ -> Nothing
                    , onResizeStarted = Nothing
                    , onResizeEnded = Nothing
                    }
                )
                msg
                model
    in
        updatedModel


{-| Updates internal model using custom configuration.
-}
customUpdate : UpdateConfig msg -> Msg -> State -> ( State, Maybe msg )
customUpdate (UpdateConfig updateConfig) msg (State state) =
    case ( state.dragState, msg ) of
        ( Draggable Nothing, SplitterClick pos ) ->
            ( State
                { state
                    | dragState =
                        Draggable <|
                            Just
                                { paneInfo =
                                    { width = pos.parentWidth
                                    , height = pos.parentHeight
                                    }
                                , anchor =
                                    { x = Maybe.withDefault 0 pos.x
                                    , y = Maybe.withDefault 0 pos.y
                                    }
                                }
                }
            , updateConfig.onResizeStarted
            )

        ( Draggable (Just _), SplitterLeftAlone _ ) ->
            ( State { state | dragState = Draggable Nothing }
            , updateConfig.onResizeEnded
            )

        ( Draggable (Just { paneInfo, anchor }), SplitterMove newRequestedPosition ) ->
            let
                step =
                    { x = newRequestedPosition.clientX - anchor.x
                    , y = newRequestedPosition.clientY - anchor.y
                    }

                newSplitterPosition =
                    resize state.orientation state.splitterPosition step paneInfo.width paneInfo.height
            in
                ( State
                    { state
                        | splitterPosition = newSplitterPosition
                        , dragState =
                            Draggable <|
                                Just
                                    { paneInfo =
                                        { width = paneInfo.width
                                        , height = paneInfo.height
                                        }
                                    , anchor =
                                        { x = newRequestedPosition.clientX
                                        , y = newRequestedPosition.clientY
                                        }
                                    }
                    }
                , updateConfig.onResize newSplitterPosition
                )

        _ ->
            ( State state, Nothing )


resize : Orientation -> SizeUnit -> Position -> Int -> Int -> SizeUnit
resize o splitterPosition step paneWidth paneHeight =
    case o of
        Horizontal ->
            case splitterPosition of
                Px pxx ->
                    Px <| updateValue (\v -> v + step.x) pxx

                Percentage p ->
                    Percentage <| updateValue (\v -> v + toFloat step.x / toFloat paneWidth) p

        Vertical ->
            case splitterPosition of
                Px pxx ->
                    Px <| updateValue (\v -> v + step.y) pxx

                Percentage p ->
                    Percentage <| updateValue (\v -> v + toFloat step.y / toFloat paneHeight) p



-- VIEW


{-| Lets you specify attributes such as style and children for the splitter element
-}
type alias HtmlDetails msg =
    { attributes : List (Attribute msg)
    , children : List (Html msg)
    }


{-| Describes a custom splitter
-}
type CustomSplitter msg
    = CustomSplitter (Html msg)


createDefaultSplitterDetails : Orientation -> DragState -> HtmlDetails msg
createDefaultSplitterDetails o dragState =
    case o of
        Horizontal ->
            { attributes =
                 defaultHorizontalSplitterStyle dragState
            , children = []
            }

        Vertical ->
            { attributes =
                 defaultVerticalSplitterStyle dragState
            , children = []
            }


{-| Creates a custom splitter.

        myCustomSplitter : CustomSplitter Msg
        myCustomSplitter =
            createCustomSplitter PaneMsg
                { attributes =
                    [ style
                        [ ( "width", "20px" )
                        , ( "height", "20px" )
                        ]
                    ]
                , children =
                    []
                }
-}
createCustomSplitter :
    (Msg -> msg)
    -> HtmlDetails msg
    -> CustomSplitter msg
createCustomSplitter toMsg details =
    CustomSplitter <|
        span
            (onMouseDown toMsg :: onTouchStart toMsg :: onTouchEnd toMsg :: onTouchMove toMsg :: onTouchCancel toMsg :: details.attributes)
            details.children


{-| Configuration for the view.
-}
type ViewConfig msg
    = ViewConfig
        { toMsg : Msg -> msg
        , splitter : Maybe (CustomSplitter msg)
        }


{-| Creates a configuration for the view.
-}
createViewConfig :
    { toMsg : Msg -> msg
    , customSplitter : Maybe (CustomSplitter msg)
    }
    -> ViewConfig msg
createViewConfig { toMsg, customSplitter } =
    ViewConfig
        { toMsg = toMsg
        , splitter = customSplitter
        }


{-| Creates a view.

        view : Model -> Html Msg
        view =
            SplitPane.view viewConfig firstView secondView


        viewConfig : ViewConfig Msg
        viewConfig =
            createViewConfig
                { toMsg = PaneMsg
                , customSplitter = Nothing
                }

        firstView : Html a
        firstView =
            img [ src "http://4.bp.blogspot.com/-s3sIvuCfg4o/VP-82RkCOGI/AAAAAAAALSY/509obByLvNw/s1600/baby-cat-wallpaper.jpg" ] []


        secondView : Html a
        secondView =
            img [ src "http://2.bp.blogspot.com/-pATX0YgNSFs/VP-82AQKcuI/AAAAAAAALSU/Vet9e7Qsjjw/s1600/Cat-hd-wallpapers.jpg" ] []
-}
view : ViewConfig msg -> Html msg -> Html msg -> State -> Html msg
view (ViewConfig viewConfig) firstView secondView (State state) =
    let
        splitter =
            getConcreteSplitter viewConfig state.orientation state.dragState
    in
        div
            ([ class "pane-container"
            
            ] ++ paneContainerStyle state.orientation)
            [ div
                ([ class "pane-first-view"
                ] ++ firstChildViewStyle (State state))
                [ firstView ]
            , splitter
            , div
                ([ class "pane-second-view"
                ] ++ secondChildViewStyle (State state))
                [ secondView ]
            ]


getConcreteSplitter :
    { toMsg : Msg -> msg
    , splitter : Maybe (CustomSplitter msg)
    }
    -> Orientation
    -> DragState
    -> Html msg
getConcreteSplitter viewConfig o dragState =
    case viewConfig.splitter of
        Just (CustomSplitter splitter) ->
            splitter

        Nothing ->
            case createCustomSplitter viewConfig.toMsg <| createDefaultSplitterDetails o dragState of
                CustomSplitter defaultSplitter ->
                    defaultSplitter



-- STYLES
styles : List (String, String) -> List (Attribute msg)
styles s =
    List.map (\(k, v) ->
        style k v) s

paneContainerStyle : Orientation -> List (Attribute msg)
paneContainerStyle o =
    styles
        [ ( "overflow", "hidden" )
        , ( "display", "flex" )
        , ( "flexDirection"
          , case o of
                Horizontal ->
                    "row"

                Vertical ->
                    "column"
          )
        , ( "justifyContent", "center" )
        , ( "alignItems", "center" )
        , ( "width", "100%" )
        , ( "height", "100%" )
        , ( "boxSizing", "border-box" )
        ]


firstChildViewStyle : State -> List (Attribute msg)
firstChildViewStyle (State state) =
    case state.splitterPosition of
        Px pxx ->
            let
                v =
                    (String.fromFloat <| toFloat (getValue pxx)) ++ "px"
            in
                case state.orientation of
                    Horizontal ->
                        styles
                            [ ( "display", "flex" )
                            , ( "width", v )
                            , ( "height", "100%" )
                            , ( "overflow", "hidden" )
                            , ( "boxSizing", "border-box" )
                            , ( "position", "relative" )
                            ]

                    Vertical ->
                        styles
                            [ ( "display", "flex" )
                            , ( "width", "100%" )
                            , ( "height", v )
                            , ( "overflow", "hidden" )
                            , ( "boxSizing", "border-box" )
                            , ( "position", "relative" )
                            ]

        Percentage p ->
            let
                v =
                    getValue p |> String.fromFloat
            in
                styles
                    [ ( "display", "flex" )
                    , ( "flex", v )
                    , ( "width", "100%" )
                    , ( "height", "100%" )
                    , ( "overflow", "hidden" )
                    , ( "boxSizing", "border-box" )
                    , ( "position", "relative" )
                    ]


secondChildViewStyle : State -> List (Attribute msg)
secondChildViewStyle (State state) =
    case state.splitterPosition of
        Px _ ->
            styles
                [ ( "display", "flex" )
                , ( "flex", "1" )
                , ( "width", "100%" )
                , ( "height", "100%" )
                , ( "overflow", "hidden" )
                , ( "boxSizing", "border-box" )
                , ( "position", "relative" )
                ]

        Percentage p ->
            let
                v =
                    1 - getValue p |> String.fromFloat
            in
                styles
                    [ ( "display", "flex" )
                    , ( "flex", v )
                    , ( "width", "100%" )
                    , ( "height", "100%" )
                    , ( "overflow", "hidden" )
                    , ( "boxSizing", "border-box" )
                    , ( "position", "relative" )
                    ]


defaultVerticalSplitterStyle : DragState -> List (Attribute msg)
defaultVerticalSplitterStyle dragState =
    styles
        (baseDefaultSplitterStyles
            ++ [ ( "height", "11px" )
               , ( "width", "100%" )
               , ( "margin", "-5px 0" )
               , ( "borderTop", "5px solid rgba(255, 255, 255, 0)" )
               , ( "borderBottom", "5px solid rgba(255, 255, 255, 0)" )
               ]
            ++ case dragState of
                Draggable _ ->
                    [ ( "cursor", "row-resize" ) ]

                NotDraggable ->
                    []
        )


defaultHorizontalSplitterStyle : DragState -> List (Attribute msg)
defaultHorizontalSplitterStyle dragState =
    styles
        (baseDefaultSplitterStyles
            ++ [ ( "width", "11px" )
               , ( "height", "100%" )
               , ( "margin", "0 -5px" )
               , ( "borderLeft", "5px solid rgba(255, 255, 255, 0)" )
               , ( "borderRight", "5px solid rgba(255, 255, 255, 0)" )
               ]
            ++ case dragState of
                Draggable _ ->
                    [ ( "cursor", "col-resize" ) ]

                NotDraggable ->
                    []
        )


baseDefaultSplitterStyles : List ( String, String )
baseDefaultSplitterStyles =
    [ ( "width", "100%" )
    , ( "background", "#000" )
    , ( "boxSizing", "border-box" )
    , ( "opacity", ".2" )
    , ( "zIndex", "1" )
    , ( "webkitUserSelect", "none" )
    , ( "mozUserSelect", "none" )
    , ( "userSelect", "none" )
    , ( "backgroundClip", "padding-box" )
    ]



-- EVENT HANDLERS


onMouseDown : (Msg -> msg) -> Attribute msg
onMouseDown toMsg =
    let
        options message =
            { message = message
            , preventDefault = True
            , stopPropagation = True
            }
        decoder = 
            Json.map (toMsg << SplitterClick) domInfo
            |> Json.map options
    in
        custom "mousedown" decoder


onTouchStart : (Msg -> msg) -> Attribute msg
onTouchStart toMsg =
    let
        options message =
            { message = message
            , preventDefault = True
            , stopPropagation = True
            }
        decoder = 
            Json.map (toMsg << SplitterClick) domInfo
            |> Json.map options
    in
        custom "touchstart" decoder


onTouchEnd : (Msg -> msg) -> Attribute msg
onTouchEnd toMsg =
    let
        options message =
            { message = message
            , preventDefault = True
            , stopPropagation = True
            }
        decoder = 
            Json.map (toMsg << SplitterClick) domInfo
            |> Json.map options
    in
        custom "touchend" decoder


onTouchCancel : (Msg -> msg) -> Attribute msg
onTouchCancel toMsg =
    let
        options message =
            { message = message
            , preventDefault = True
            , stopPropagation = True
            }
        decoder = 
            Json.map (toMsg << SplitterClick) domInfo
            |> Json.map options
    in
        custom "touchcancel" decoder


onTouchMove : (Msg -> msg) -> Attribute msg
onTouchMove toMsg =
    let
        options message =
            { message = message
            , preventDefault = True
            , stopPropagation = True
            }
        decoder = 
            Json.map (toMsg << SplitterClick) domInfo
            |> Json.map options
    in
        custom "touchmove" decoder


{-| The position of the touch relative to the whole document. So if you are
scrolled down a bunch, you are still getting a coordinate relative to the
very top left corner of the *whole* document.
-}
type alias DOMInfo =
    { x : Maybe Int
    , y : Maybe Int
    , touchX : Maybe Int
    , touchY : Maybe Int
    , parentWidth : Int
    , parentHeight : Int
    }


{-| The decoder used to extract a `DOMInfo` from a JavaScript touch event.
-}
domInfo : Json.Decoder DOMInfo
domInfo =
    Json.map6 DOMInfo
        (Json.maybe (field "clientX" Json.int))
        (Json.maybe (field "clientY" Json.int))
        (Json.maybe (at [ "touches", "0", "clientX" ] Json.int))
        (Json.maybe (at [ "touches", "0", "clientY" ] Json.int))
        (at [ "currentTarget", "parentElement", "clientWidth" ] Json.int)
        (at [ "currentTarget", "parentElement", "clientHeight" ] Json.int)


mousePositionDecoder :  Json.Decoder MousePosition
mousePositionDecoder =
    Json.succeed MousePosition
    |> required "clientX" Json.int
    |> required "clientY" Json.int
    |> required "pageX" Json.int
    |> required "pageY" Json.int
    |> required "screenX" Json.int
    |> required "screenY" Json.int
    |> required "offsetX" Json.int
    |> required "offsetY" Json.int


-- SUBSCRIPTIONS


{-| Subscribes to relevant events for resizing
-}
subscriptions : State -> Sub Msg
subscriptions (State state) =
    case state.dragState of
        Draggable (Just _) ->
            Sub.batch
                [ Sub.map SplitterMove (BEvents.onMouseMove mousePositionDecoder)
                , Sub.map SplitterLeftAlone (BEvents.onMouseUp mousePositionDecoder)
                ]
        _ ->
            Sub.none

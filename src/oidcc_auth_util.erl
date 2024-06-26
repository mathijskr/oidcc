%%%-------------------------------------------------------------------
%% @doc Authentication Utilities
%% @end
%%%-------------------------------------------------------------------
-module(oidcc_auth_util).

-feature(maybe_expr, enable).

-include("oidcc_client_context.hrl").
-include("oidcc_provider_configuration.hrl").

-include_lib("jose/include/jose_jwk.hrl").

-export_type([auth_method/0, error/0]).

-type auth_method() ::
    none | client_secret_basic | client_secret_post | client_secret_jwt | private_key_jwt.

-type error() :: no_supported_auth_method.

-export([add_client_authentication/6]).

%% @private
-spec add_client_authentication(
    QueryList, Header, SupportedAuthMethods, AllowAlgorithms, Opts, ClientContext
) ->
    {ok, {oidcc_http_util:query_params(), [oidcc_http_util:http_header()]}}
    | {error, error()}
when
    QueryList :: oidcc_http_util:query_params(),
    Header :: [oidcc_http_util:http_header()],
    SupportedAuthMethods :: [binary()] | undefined,
    AllowAlgorithms :: [binary()] | undefined,
    Opts :: map(),
    ClientContext :: oidcc_client_context:t().
add_client_authentication(_QueryList, _Header, undefined, _AllowAlgs, _Opts, _ClientContext) ->
    {error, no_supported_auth_method};
add_client_authentication(
    QueryList0, Header0, SupportedAuthMethods, AllowAlgorithms, Opts, ClientContext
) ->
    PreferredAuthMethods = maps:get(preferred_auth_methods, Opts, [
        private_key_jwt,
        client_secret_jwt,
        client_secret_post,
        client_secret_basic,
        none
    ]),
    case select_preferred_auth(PreferredAuthMethods, SupportedAuthMethods) of
        {ok, AuthMethod} ->
            case
                add_authentication(QueryList0, Header0, AuthMethod, AllowAlgorithms, ClientContext)
            of
                {ok, {QueryList, Header}} ->
                    {ok, {QueryList, Header}};
                {error, _} ->
                    add_client_authentication(
                        QueryList0,
                        Header0,
                        SupportedAuthMethods -- [atom_to_binary(AuthMethod)],
                        AllowAlgorithms,
                        Opts,
                        ClientContext
                    )
            end;
        {error, Reason} ->
            {error, Reason}
    end.

-spec add_authentication(
    QueryList,
    Header,
    AuthMethod,
    AllowAlgorithms,
    ClientContext
) ->
    {ok, {oidcc_http_util:query_params(), [oidcc_http_util:http_header()]}}
    | {error, auth_method_not_possible}
when
    QueryList :: oidcc_http_util:query_params(),
    Header :: [oidcc_http_util:http_header()],
    AuthMethod :: auth_method(),
    AllowAlgorithms :: [binary()] | undefined,
    ClientContext :: oidcc_client_context:t().
add_authentication(
    QsBodyList,
    Header,
    none,
    _AllowArgs,
    #oidcc_client_context{client_id = ClientId}
) ->
    NewBodyList = [{<<"client_id">>, ClientId} | QsBodyList],
    {ok, {NewBodyList, Header}};
add_authentication(
    _QsBodyList,
    _Header,
    _Method,
    _AllowAlgs,
    #oidcc_client_context{client_secret = unauthenticated}
) ->
    {error, auth_method_not_possible};
add_authentication(
    QsBodyList,
    Header,
    client_secret_basic,
    _AllowAlgs,
    #oidcc_client_context{client_id = ClientId, client_secret = ClientSecret}
) ->
    NewHeader = [oidcc_http_util:basic_auth_header(ClientId, ClientSecret) | Header],
    {ok, {QsBodyList, NewHeader}};
add_authentication(
    QsBodyList,
    Header,
    client_secret_post,
    _AllowAlgs,
    #oidcc_client_context{client_id = ClientId, client_secret = ClientSecret}
) ->
    NewBodyList =
        [{<<"client_id">>, ClientId}, {<<"client_secret">>, ClientSecret} | QsBodyList],
    {ok, {NewBodyList, Header}};
add_authentication(
    QsBodyList,
    Header,
    client_secret_jwt,
    AllowAlgorithms,
    ClientContext
) ->
    #oidcc_client_context{
        client_secret = ClientSecret
    } = ClientContext,

    maybe
        [_ | _] ?= AllowAlgorithms,
        #jose_jwk{} =
            OctJwk ?=
                oidcc_jwt_util:client_secret_oct_keys(
                    AllowAlgorithms,
                    ClientSecret
                ),
        {ok, ClientAssertion} ?=
            signed_client_assertion(
                AllowAlgorithms,
                ClientContext,
                OctJwk
            ),
        {ok, add_jwt_bearer_assertion(ClientAssertion, QsBodyList, Header, ClientContext)}
    else
        _ ->
            {error, auth_method_not_possible}
    end;
add_authentication(
    QsBodyList,
    Header,
    private_key_jwt,
    AllowAlgorithms,
    ClientContext
) ->
    #oidcc_client_context{
        client_jwks = ClientJwks
    } = ClientContext,

    maybe
        [_ | _] ?= AllowAlgorithms,
        #jose_jwk{} ?= ClientJwks,
        {ok, ClientAssertion} ?=
            signed_client_assertion(AllowAlgorithms, ClientContext, ClientJwks),
        {ok, add_jwt_bearer_assertion(ClientAssertion, QsBodyList, Header, ClientContext)}
    else
        _ ->
            {error, auth_method_not_possible}
    end.

-spec select_preferred_auth(PreferredAuthMethods, AuthMethodsSupported) ->
    {ok, auth_method()} | {error, error()}
when
    PreferredAuthMethods :: [auth_method(), ...],
    AuthMethodsSupported :: [binary()].
select_preferred_auth(PreferredAuthMethods, AuthMethodsSupported) ->
    PreferredAuthMethodSearchFun = fun(AuthMethod) ->
        lists:member(atom_to_binary(AuthMethod), AuthMethodsSupported)
    end,

    case lists:search(PreferredAuthMethodSearchFun, PreferredAuthMethods) of
        {value, AuthMethod} ->
            {ok, AuthMethod};
        false ->
            {error, no_supported_auth_method}
    end.

-spec signed_client_assertion(AllowAlgorithms, ClientContext, Jwk) ->
    {ok, binary()} | {error, term()}
when
    AllowAlgorithms :: [binary()],
    Jwk :: jose_jwk:key(),
    ClientContext :: oidcc_client_context:t().
signed_client_assertion(AllowAlgorithms, ClientContext, Jwk) ->
    Jwt = jose_jwt:from(token_request_claims(ClientContext)),

    oidcc_jwt_util:sign(Jwt, Jwk, AllowAlgorithms).

-spec token_request_claims(ClientContext) -> oidcc_jwt_util:claims() when
    ClientContext :: oidcc_client_context:t().
token_request_claims(#oidcc_client_context{
    client_id = ClientId,
    provider_configuration = #oidcc_provider_configuration{token_endpoint = TokenEndpoint}
}) ->
    MaxClockSkew =
        case application:get_env(oidcc, max_clock_skew) of
            undefined -> 0;
            {ok, ClockSkew} -> ClockSkew
        end,

    #{
        <<"iss">> => ClientId,
        <<"sub">> => ClientId,
        <<"aud">> => TokenEndpoint,
        <<"jti">> => random_string(32),
        <<"iat">> => os:system_time(seconds),
        <<"exp">> => os:system_time(seconds) + 30,
        <<"nbf">> => os:system_time(seconds) - MaxClockSkew
    }.

-spec add_jwt_bearer_assertion(ClientAssertion, Body, Header, ClientContext) -> {Body, Header} when
    ClientAssertion :: binary(),
    Body :: oidcc_http_util:query_params(),
    Header :: [oidcc_http_util:http_header()],
    ClientContext :: oidcc_client_context:t().
add_jwt_bearer_assertion(ClientAssertion, Body, Header, ClientContext) ->
    #oidcc_client_context{client_id = ClientId} = ClientContext,
    {
        [
            {<<"client_assertion_type">>,
                <<"urn:ietf:params:oauth:client-assertion-type:jwt-bearer">>},
            {<<"client_assertion">>, ClientAssertion},
            {<<"client_id">>, ClientId}
            | Body
        ],
        Header
    }.

-spec random_string(Bytes :: pos_integer()) -> binary().
random_string(Bytes) ->
    base64:encode(crypto:strong_rand_bytes(Bytes), #{mode => urlsafe, padding => false}).

%%%-------------------------------------------------------------------
%% @doc Client Configuration for authorization, token exchange and
%% userinfo
%%
%% For most projects, it makes sense to use
%% {@link oidcc_provider_configuration_worker} and the high-level
%% interface of {@link oidcc}. In that case direct usage of this
%% module is not needed.
%%
%% To use the record, import the definition:
%%
%% ```
%% -include_lib(["oidcc/include/oidcc_client_context.hrl"]).
%% '''
%% @end
%% @since 3.0.0
%%%-------------------------------------------------------------------
-module(oidcc_client_context).

-include("oidcc_client_context.hrl").
-include("oidcc_provider_configuration.hrl").

-include_lib("jose/include/jose_jwk.hrl").

-export_type([authenticated_opts/0]).
-export_type([authenticated_t/0]).
-export_type([error/0]).
-export_type([opts/0]).
-export_type([t/0]).
-export_type([unauthenticated_opts/0]).
-export_type([unauthenticated_t/0]).

-export([from_configuration_worker/3]).
-export([from_configuration_worker/4]).
-export([from_manual/4]).
-export([from_manual/5]).

-type t() :: authenticated_t() | unauthenticated_t().

-type authenticated_t() :: #oidcc_client_context{
    provider_configuration :: oidcc_provider_configuration:t(),
    jwks :: jose_jwk:key(),
    client_id :: binary(),
    client_secret :: binary(),
    client_jwks :: jose_jwk:key() | none
}.

-type unauthenticated_t() :: #oidcc_client_context{
    provider_configuration :: oidcc_provider_configuration:t(),
    jwks :: jose_jwk:key(),
    client_id :: binary(),
    client_secret :: unauthenticated,
    client_jwks :: none
}.

-type authenticated_opts() :: #{
    client_jwks => jose_jwk:key()
}.
-type unauthenticated_opts() :: #{}.

-type opts() :: authenticated_opts() | unauthenticated_opts().

-type error() :: provider_not_ready.

%% @doc Create Client Context from a {@link oidcc_provider_configuration_worker}
%%
%% See {@link from_configuration_worker/4}
%% @end
%% @since 3.0.0
-spec from_configuration_worker
    (ProviderName, ClientId, ClientSecret) -> {ok, authenticated_t()} | {error, error()} when
        ProviderName :: gen_server:server_ref(),
        ClientId :: binary(),
        ClientSecret :: binary();
    (ProviderName, ClientId, ClientSecret) -> {ok, unauthenticated_t()} | {error, error()} when
        ProviderName :: gen_server:server_ref(),
        ClientId :: binary(),
        ClientSecret :: unauthenticated.
from_configuration_worker(ProviderName, ClientId, ClientSecret) ->
    from_configuration_worker(ProviderName, ClientId, ClientSecret, #{}).

%% @doc Create Client Context from a {@link oidcc_provider_configuration_worker}
%%
%% <h2>Examples</h2>
%%
%% ```
%% {ok, Pid} =
%%   oidcc_provider_configuration_worker:start_link(#{
%%     issuer => <<"https://login.salesforce.com">>
%%   }),
%%
%% {ok, #oidcc_client_context{}} =
%%   oidcc_client_context:from_configuration_worker(Pid,
%%                                                  <<"client_id">>,
%%                                                  <<"client_secret">>).
%% '''
%%
%% ```
%% {ok, Pid} =
%%   oidcc_provider_configuration_worker:start_link(#{
%%     issuer => <<"https://login.salesforce.com">>,
%%     name => {local, salesforce_provider}
%%   }),
%%
%% {ok, #oidcc_client_context{}} =
%%   oidcc_client_context:from_configuration_worker($
%%     salesforce_provider,
%%     <<"client_id">>,
%%     <<"client_secret">>,
%%     #{client_jwks => jose_jwk:generate_key(16)}
%% ).
%% '''
%% @end
%% @since 3.0.0
-spec from_configuration_worker
    (ProviderName, ClientId, ClientSecret, Opts) ->
        {ok, authenticated_t()} | {error, error()}
    when
        ProviderName :: gen_server:server_ref(),
        ClientId :: binary(),
        ClientSecret :: binary(),
        Opts :: authenticated_opts();
    (ProviderName, ClientId, ClientSecret, Opts) ->
        {ok, unauthenticated_t()} | {error, error()}
    when
        ProviderName :: gen_server:server_ref(),
        ClientId :: binary(),
        ClientSecret :: unauthenticated,
        Opts :: unauthenticated_opts().
from_configuration_worker(ProviderName, ClientId, ClientSecret, Opts) when is_pid(ProviderName) ->
    {ok,
        from_manual(
            oidcc_provider_configuration_worker:get_provider_configuration(ProviderName),
            oidcc_provider_configuration_worker:get_jwks(ProviderName),
            ClientId,
            ClientSecret,
            Opts
        )};
from_configuration_worker(ProviderName, ClientId, ClientSecret, Opts) ->
    case erlang:whereis(ProviderName) of
        undefined ->
            {error, provider_not_ready};
        Pid ->
            from_configuration_worker(Pid, ClientId, ClientSecret, Opts)
    end.

%% @doc Create Client Context manually
%%
%% See {@link from_manual/5}
%% @end
%% @since 3.0.0
-spec from_manual
    (Configuration, Jwks, ClientId, ClientSecret) -> authenticated_t() when
        Configuration :: oidcc_provider_configuration:t(),
        Jwks :: jose_jwk:key(),
        ClientId :: binary(),
        ClientSecret :: binary();
    (Configuration, Jwks, ClientId, ClientSecret) -> unauthenticated_t() when
        Configuration :: oidcc_provider_configuration:t(),
        Jwks :: jose_jwk:key(),
        ClientId :: binary(),
        ClientSecret :: unauthenticated.
from_manual(Configuration, Jwks, ClientId, ClientSecret) ->
    from_manual(Configuration, Jwks, ClientId, ClientSecret, #{}).

%% @doc Create Client Context manually
%%
%% <h2>Examples</h2>
%%
%% ```
%% {ok, Configuration} =
%%   oidcc_provider_configuration:load_configuration(<<"https://login.salesforce.com">>,
%%                                              []),
%%
%% #oidcc_provider_configuration{jwks_uri = JwksUri} = Configuration,
%%
%% {ok, Jwks} = oidcc_provider_configuration:load_jwks(JwksUri, []).
%%
%% #oidcc_client_context{} =
%%   oidcc_client_context:from_manual(
%%     Metdata,
%%     Jwks,
%%     <<"client_id">>,
%%     <<"client_secret">>,
%%     #{client_jwks => jose_jwk:generate_key(16)}
%% ).
%% '''
%% @end
%% @since 3.0.0
-spec from_manual
    (Configuration, Jwks, ClientId, ClientSecret, Opts) -> authenticated_t() when
        Configuration :: oidcc_provider_configuration:t(),
        Jwks :: jose_jwk:key(),
        ClientId :: binary(),
        ClientSecret :: binary(),
        Opts :: authenticated_opts();
    (Configuration, Jwks, ClientId, ClientSecret, Opts) -> unauthenticated_t() when
        Configuration :: oidcc_provider_configuration:t(),
        Jwks :: jose_jwk:key(),
        ClientId :: binary(),
        ClientSecret :: unauthenticated,
        Opts :: unauthenticated_opts().
from_manual(
    #oidcc_provider_configuration{} = Configuration,
    #jose_jwk{} = Jwks,
    ClientId,
    unauthenticated,
    _Opts
) when is_binary(ClientId) ->
    #oidcc_client_context{
        provider_configuration = Configuration,
        jwks = Jwks,
        client_id = ClientId,
        client_secret = unauthenticated
    };
from_manual(
    #oidcc_provider_configuration{} = Configuration,
    #jose_jwk{} = Jwks,
    ClientId,
    ClientSecret,
    Opts
) when is_binary(ClientId), is_binary(ClientSecret) ->
    #oidcc_client_context{
        provider_configuration = Configuration,
        jwks = Jwks,
        client_id = ClientId,
        client_secret = ClientSecret,
        client_jwks = maps:get(client_jwks, Opts, none)
    }.

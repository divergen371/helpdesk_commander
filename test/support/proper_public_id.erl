-module(proper_public_id).

-include_lib("proper/include/proper.hrl").

-export([prop_public_id/0]).

prop_public_id() ->
  ?FORALL(Half, integer(1, 32),
    begin
      Len = Half * 2,
      Id = 'Elixir.HelpdeskCommander.Support.PublicId':generate(Len),
      byte_size(Id) =:= Len andalso
        re:run(Id, "^[0-9a-f]+$") =/= nomatch
    end).

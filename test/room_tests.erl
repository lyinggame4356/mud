-module(room_tests).
-include("../src/records.hrl").
-include_lib("stdlib/include/qlc.hrl").
-include("tests.hrl").

room_test_() -> [
 ?Describe("Taking an item from the room",
   [?It("should remove it from the room", fun setup/0, fun cleanup/1,
        begin
        ok = room:add_to_room(kitchen, "a wrench"),
        {ok, Item} = room:take_from_room(kitchen, "a wrench"),
        {ok, Description} = room:describe(kitchen),
        ?assertEqual("a wrench", Item),
        ?assertEqual("It's a kitchen",Description) end),
    ?It("should handle an item not in the list", fun setup/0, fun cleanup/1,
        begin
        ok = room:add_to_room(kitchen, "a wombat"),
        {not_found, Item} = room:take_from_room(kitchen, "a wrench"),
        ?assertEqual("a wrench", Item) end),
    ?It("should handle an empty list", fun setup/0, fun cleanup/1,
        begin
        {not_found, Item} = room:take_from_room(kitchen, "a wrench"),
        ?assertEqual("a wrench", Item) end)
 ]),
 ?Describe("Adding an item to the room",
   [?It("should show in the description", fun setup/0, fun cleanup/1,
        begin
	ok = room:add_to_room(kitchen, "a wrench"),
        {ok,Description} = room:describe(kitchen),
        ?assertEqual("It's a kitchen\n\ta wrench",Description)end),
    ?It("should show multiple items", fun setup/0, fun cleanup/1,
        begin
        ok = room:add_to_room(kitchen, "a wrench"),
        ok = room:add_to_room(kitchen, "a wombat"),
        {ok,Description} = room:describe(kitchen),
        ?assertEqual("It's a kitchen\n\ta wrench\n\ta wombat",Description)end)
   ]) 
].

room_database_test_() -> [
  ?Describe("load from the database",
    [?It("should load a stable from the database",
         fun insert_stable/0, fun delete_stable/1,
         begin
         room:start_from_db(stable),
         {ok,Description} = room:describe(stable),
         ?assertEqual("A stable from the database",Description)
         end),
     ?It("should start multiple rooms",
         fun insert_stable/0, fun delete_stable/1,
         begin
         room:start_from_db(),
         {ok,Description1} = room:describe(stable),
         {ok,Description2} = room:describe(yard),
         ?assertEqual("A stable from the database", Description1),
         ?assertEqual("A yard from the database", Description2)
         end)
  ]),
  ?Describe("Update the database when changes happen",
    [?It("should save when items are dropped",
         fun insert_stable/0, fun delete_stable/1,
         begin
         room:start_from_db(stable),
         ok = room:add_to_room(stable, "a wrench"),
         {atomic, Rows} = mnesia:transaction(fun() ->
                qlc:eval( qlc:q([ X || X <- mnesia:table(room)])) end),
         [Stable] = lists:filter((fun (X) -> stable == X#room.key end), Rows),
         ?assertEqual(["a wrench"], Stable#room.items)
         end),
     ?It("Should save when items are picked up",
         fun insert_stable/0, fun delete_stable/1,
         begin
         room:start_from_db(stable),
         ok = room:add_to_room(stable, "a wrench"),
         {ok, "a wrench"} = room:take_from_room(stable, "a wrench"),
         {atomic, Rows} = mnesia:transaction(fun() ->
                qlc:eval( qlc:q([ X || X <- mnesia:table(room)])) end),
         [Stable] = lists:filter((fun (X) -> stable == X#room.key end), Rows),
         ?assertEqual([], Stable#room.items)
         end)
  ]),
  ?Describe("Create Rooms",
    [?It("Should insert a new room in to the database",
         fun setup/0, (fun (Pid) -> 
                         room:destroy_room(park),
                         cleanup(Pid) end),
         begin
         room:create_room(park, "The Park", "A green park with a small swingset"),
         {atomic, Rows} = mnesia:transaction(fun() ->
           qlc:eval( qlc:q([ X || X <- mnesia:table(room)])) end),
         [Park] = lists:filter((fun (X) -> park == X#room.key end), Rows),
         ?assertEqual([], Park#room.items)
         end),
     ?It("Should start the room",
         fun setup/0, (fun (Pid) -> 
                         room:destroy_room(park),
                         cleanup(Pid) end),
         begin
         room:create_room(park, "The Park", "A green park with a small swingset"),
         {ok, Description} = room:describe(park),
         ?assertEqual("A green park with a small swingset", Description)
         end)
  ]),
  ?Describe("Destroy Room",
    [?It("should stop a room",
         fun setup/0, fun cleanup/1,
         begin
         room:create_room(office, "An Office", "Some Description"),
         room:destroy_room(office),
         Names = global:registered_names(),
         Name = lists:filter((fun (X) -> X == office end), Names),
         ?assertEqual([], Name)
         end) ,
     ?It("should remove a room from the database",
         fun setup/0, fun cleanup/1,
         begin
         room:create_room(office, "An Office", "Some Description"),
         room:destroy_room(office),
         {atomic, Rows} = mnesia:transaction(fun() ->
           qlc:eval( qlc:q([ X || X <- mnesia:table(room)])) end),
         OfficeQuery = lists:filter((fun (X) -> office == X#room.key end), Rows),
         ?assertEqual([], OfficeQuery)
         end)
  ]),
  ?Describe("Add an Exit to a room",
    [?It("should add an exit to a room",
         fun setup/0, fun cleanup/1,
	 begin
	 room:create_exit(lobby, kitchen, "stairs", "A Staircase leading down"),
	 Response = room:direction(lobby, "stairs"),
	 ?assertEqual({ok, kitchen}, Response)
	 end)
    ])
].

insert_stable() ->
        mnesia:transaction(fun() ->
                mnesia:write(
                 #room{key=yard,
                       name="The horse yard",
                       description="A yard from the database"}
                ),
                mnesia:write(
                 #room{key=stable,
                       name="The king's stable",
                       description="A stable from the database"}
                )
                end).


delete_stable(_Pid) ->
        gen_server:cast({global, stable}, stop),
        gen_server:cast({global, yard}, stop),
        mnesia:transaction(fun() ->
                           mnesia:delete({room, yard}),
                           mnesia:delete({room, stable}) end),
        true.

setup()-> io:format(""),stubs:fake_rooms().
cleanup(_Pid) -> stubs:stop_fake_rooms(), true.

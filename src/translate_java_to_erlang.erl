%% Copyright (c) 2011, Lars-Ake Fredlund
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions are met:
%%     %% Redistributions of source code must retain the above copyright
%%       notice, this list of conditions and the following disclaimer.
%%     %% Redistributions in binary form must reproduce the above copyright
%%       notice, this list of conditions and the following disclaimer in the
%%       documentation and/or other materials provided with the distribution.
%%     %% Neither the name of the copyright holders nor the
%%       names of its contributors may be used to endorse or promote products
%%       derived from this software without specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ''AS IS''
%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
%% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
%% BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
%% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
%% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

%% @author Lars-Ake Fredlund (lfredlund@fi.upm.es)
%% @copyright 2011 Lars-Ake Fredlund
%%

-module(translate_java_to_erlang).
%%-compile(export_all).

-export([gen_java_erlang_module/2]).

-include("classinfo.hrl").

-record(comp_info,{type,className,methodConstructor,methodFieldAccess,methodAccess,genMethodFun,methodFun,node_id}).

-include("debug.hrl").

ensure_string(Atom) when is_atom(Atom) ->
  atom_to_list(Atom);
ensure_string(List) when is_list(List) ->
  List.

gen_java_erlang_module(NodeId,ClassName) when is_list(ClassName) ->
  gen_java_erlang_module(NodeId,list_to_atom(ClassName));
gen_java_erlang_module(NodeId,ClassName) when is_atom(ClassName) ->
  ?LOG("[generating java module for ~p...]~n",[ClassName]),
  ClassInfo = java:get_class_info(NodeId,true,ClassName),
  JavaSources = java:get_option(java_sources,NodeId),
  case file:read_file_info(JavaSources) of
    {error,_} -> file:make_dir(JavaSources);
    _ -> ok
  end,
  FinalClassName = java:classname(ClassName,NodeId),
  IsTemporary = FinalClassName=/=ClassName,
  ErlName = ensure_string(java:to_erl_name(FinalClassName)),
  FileName = 
    if 
      IsTemporary -> "/tmp"++"/"++ErlName++".erl";
      true -> JavaSources++"/"++ErlName++".erl"
    end,
  ?LOG("FileName is ~p~n",[FileName]),
  {ok,Fd} = file:open(FileName,[write]),
  io:format(Fd,"%% WARNING: do not edit this file.~n",[]),
  io:format(Fd,"%%~n",[]),
  io:format(Fd,"%% File automatically generated using the command~n",[]),
  io:format(Fd,"%%   ~p:gen_java_erlang_module(NodeId,~p)~n",[?MODULE,ClassName]),
  io:format
    (Fd,"%% using the Java class ~s as template.~n",
     [atom_to_list(ClassName)]),
  io:format(Fd,"%%~n~n",[]),
  io:format(Fd,"-module('~s').~n",[ErlName]),
  io:format(Fd,"-compile(export_all).~n",[]),
  io:format(Fd,"-record(class,{node,constructors,methods,get_fields,set_fields,name,module_name,class_location}).~n",[]),
  io:format(Fd,"~n",[]),
  io:format
    (Fd,"class_location() -> \"~s\".~n",
     [ClassInfo#class_info.class_location]),
  io:format
    (Fd,"creation_time() -> ~p.~n~n",
     [calendar:now_to_local_time(now())]),
  io:format(Fd,"bind(NodeId) ->~n",[]),
  {ConstBindings,ConstGenericFuns,ConstFuns} = 
    bind_class_constructors
      (NodeId,ClassName,FinalClassName,ClassInfo#class_info.constructors),
  {MethodBindings,MethodGenericFuns,MethodFuns} = 
    bind_class_methods
      (NodeId,ClassName,FinalClassName,ClassInfo#class_info.methods),
  {FieldGetBindings,FieldGetGenericFuns,FieldGetFuns} = 
    bind_class_field_gets
      (NodeId,ClassName,FinalClassName,ClassInfo#class_info.fields),
  {FieldSetBindings,FieldSetGenericFuns,FieldSetFuns} = 
    bind_class_field_sets
      (NodeId,ClassName,FinalClassName,ClassInfo#class_info.fields),
  ?LOG("ClassName is ~p~n",[ClassName]),
  io:format
    (Fd,
     "  #class~n"++
     "     {node=NodeId,~n"++
     "      name=~p,~n"++
     "      class_location=\"~s\",~n"++
     "      module_name='~s',~n",
     [ClassName,ClassInfo#class_info.class_location,ErlName]),
  AroundIndent = 
    indent(6),
  InIndent =
    indent(7),
  Separator =
    ",\n"++InIndent,
  io:format
    (Fd,
     "~sconstructors=~n~s{~n~s~s~n~s},~n",
     [AroundIndent,
      AroundIndent,
      InIndent,
      combine_strings(Separator,ConstBindings),
      AroundIndent]),
  io:format
    (Fd,
     "~sget_fields=~n~s{~n~s~s~n~s},~n",
     [AroundIndent,
      AroundIndent,
      InIndent,
      combine_strings(Separator,FieldGetBindings),
      AroundIndent]),
  io:format
    (Fd,
     "~sset_fields=~n~s{~n~s~s~n~s},~n",
     [AroundIndent,
      AroundIndent,
      InIndent,
      combine_strings(Separator,FieldSetBindings),
      AroundIndent]),
  io:format
    (Fd,
     "~smethods=~n~s{~n~s~s~n~s}}.~n",
     [AroundIndent,
      AroundIndent,
      InIndent,
      combine_strings(Separator,MethodBindings),
      AroundIndent]),
  io:format
    (Fd,"~n~s~n",
     ["\n%%%%%%%%%%%%%%%%%%%%%%%%\n%% Constructors:\n\n"++
      combine_strings("\n",ConstFuns)++
      "\n\n%%%%%%%%%%%%%%%%%%%%%%%%\n%% Constructor selectors:\n\n"++
      final_symbol(".\n",combine_strings(";\n",ConstGenericFuns))++
      "\n\n%%%%%%%%%%%%%%%%%%%%%%%%\n%% Methods:\n\n"++
      combine_strings("\n",MethodFuns)++
      "\n\n%%%%%%%%%%%%%%%%%%%%%%%%\n%% Method selectors:\n\n"++
      final_symbol(".\n",combine_strings(";\n",MethodGenericFuns))++
      "\n\n%%%%%%%%%%%%%%%%%%%%%%%%\n%% Field accessors:\n\n"++
      combine_strings("\n",FieldGetFuns)++
      "\n\n%%%%%%%%%%%%%%%%%%%%%%%%\n%% Field getter selectors:\n\n"++
      final_symbol(".\n",combine_strings(";\n",FieldGetGenericFuns))++
      "\n\n%%%%%%%%%%%%%%%%%%%%%%%%\n%% Field modifiers:\n\n"++
      combine_strings("\n",FieldSetFuns)++
      "\n\n%%%%%%%%%%%%%%%%%%%%%%%%\n%% Field setter selectors:\n\n"++
      final_symbol(".\n",combine_strings(";\n",FieldSetGenericFuns))]),
  file:close(Fd),
  {FileName,IsTemporary}.

combine_strings(_Delim,[]) ->
  [];
combine_strings(_Delim,[Str]) ->
  Str;
combine_strings(Delim,[Str|Rest]) when is_list(Delim), is_list(Str) ->
  Str++Delim++combine_strings(Delim,Rest).

final_symbol(FinalSymbol,Str) ->
  if
    Str==[] -> Str;
    true -> Str++FinalSymbol
  end.

print_comma_strings(Strings) -> 
  combine_strings(",",Strings).

bind_class_constructors(NodeId,ClassName,FinalClassName,Constructors) ->
  SimpleClassName = java:finalComponent(ClassName),
  CompInfo =
    #comp_info
    {className=ClassName,
     node_id=NodeId,
     type=constructor,
     methodConstructor=
       fun (CName,_,_,Arguments) ->	
	   io_lib:format
	     ("java:constructor(NodeId,~p,~p)",
	      [CName,Arguments])
       end,
     methodFieldAccess=
       fun (N) -> {"constructors",N} end,
     methodAccess=
       fun (_,FormalParameters) ->
	   io_lib:format
	     ("~s",[print_comma_strings(FormalParameters)])
       end,
     genMethodFun=
       fun(Name,IsStatic,FormalParameters,Body) ->
	   Argument =
	     if
	       IsStatic -> "NodeId";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("'~s'(~s~s~s) ->~n  ~s~s",
	      [Name,
	       Argument,
	       if FormalParameters==[] -> ""; true -> "," end,
	       print_comma_strings(FormalParameters),
	       io_lib:format
		 ("Class = java:class_info(~s,~p),~n",
		  [Argument,ClassName]),
	       Body])
       end,
     methodFun=
       fun(_,ParameterTypes,_,FormalParameters,Field,Accessor) ->
	   io_lib:format
	     ("constructor(NodeId,~p) ->~n"++
		"  Class = java:class_info(NodeId,~p),~n"++
		"  Fun = ~s,~n"++
		"  fun (~s) ->~n"++
		"    Fun(~s)~n"++
		"  end",
	      [ParameterTypes,
	       ClassName,
	       access_element(Field),
	       print_comma_strings(FormalParameters),
	       Accessor(false,FormalParameters)])
       end},
  translate_java_elements
    (CompInfo,
     lists:map
       (fun ({_,IsStatic,Arguments}) ->
	    {SimpleClassName,IsStatic,Arguments}
	end, Constructors)).

bind_class_methods(NodeId,ClassName,FinalClassName,Methods) ->
  CompInfo =
    #comp_info
    {className=ClassName,
     node_id=NodeId,
     type=method,
     methodConstructor=
       fun (CName,Method,_,Arguments) ->
	   io_lib:format
	     ("java:method(NodeId,~p,~p,~p)",
	      [CName,Method,Arguments])
       end,
     methodFieldAccess=
       fun (N) -> {"methods",N} end,
     methodAccess=
       fun (IsStatic,FormalParameters) ->
	   Argument =
	     if
	       IsStatic -> "null";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("~s~s~s",
	      [Argument,
	       if FormalParameters==[] -> ""; true -> "," end,
	       print_comma_strings(FormalParameters)])
       end,
     genMethodFun=
       fun(Name,IsStatic,FormalParameters,Body) ->
	   Argument =
	     if
	       IsStatic -> "NodeId";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("'~s'(~s~s~s) ->~n  ~s~s",
	      [Name,
	       Argument,
	       if FormalParameters==[] -> ""; true -> "," end,
	       print_comma_strings(FormalParameters),
	       io_lib:format
		 ("Class = java:class_info(~s,~p),~n",
		  [Argument,ClassName]),
	       Body])
       end,
     methodFun=
       fun(Name,ParameterTypes,IsStatic,FormalParameters,Field,Accessor) ->
	   Argument =
	     if
	       IsStatic -> "NodeId";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("method('~s',~s,~p) ->~n"++
		"  ~s"++
		"  Fun = ~s,~n"++
		"  fun (~s) ->~n"++
		"    Fun(~s)~n"++
		"  end",
	      [Name,
	       Argument,
	       ParameterTypes,
	       io_lib:format
		 ("Class = java:class_info(~s,~p),~n",
		  [Argument,ClassName]),
	       access_element(Field),
	       print_comma_strings(FormalParameters),
	       Accessor(IsStatic,FormalParameters)])
       end},
  translate_java_elements(CompInfo,Methods).

bind_class_field_gets(NodeId,ClassName,FinalClassName,Fields) ->
  CompInfo =
    #comp_info
    {className=ClassName,
     node_id=NodeId,
     type=field_get,
     methodConstructor=
       fun (CName,Field,_,_Arguments) ->	
	   io_lib:format
	     ("java:field_get(NodeId,~p,~p)",
	      [CName,Field])
       end,
     methodFieldAccess=
       fun (N) -> {"get_fields",N} end,
     methodAccess=
       fun (IsStatic,_FormalParameters) ->
	   Argument =
	     if
	       IsStatic -> "null";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("~s",[Argument])
       end,
     genMethodFun=
       fun(Name,IsStatic,_FormalParameters,Body) ->
	   Argument =
	     if
	       IsStatic -> "NodeId";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("'get_~s'(~s) ->~n  ~s~n~s",
	      [Name,
	       Argument,
	       io_lib:format
		 ("Class = java:class_info(~s,~p),",
		  [Argument,ClassName]),
	       Body])
       end,
     methodFun=
       fun(Name,_ParameterTypes,IsStatic,FormalParameters,Field,Accessor) ->
	   Argument =
	     if
	       IsStatic -> "NodeId";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("field_get('~s',~s) ->~n"++
		"  ~s~n"++
		"  Fun = ~s,~n"++
		"  Fun(~s)",
	      [Name,
	       Argument,
	       io_lib:format
		 ("Class = java:class_info(~s,~p),",
		  [Argument,ClassName]),
	       access_element(Field),
	       Accessor(IsStatic,FormalParameters)])
       end
    },
  translate_java_elements
    (CompInfo,
     lists:map
     (fun ({Name,IsStatic,Argument}) -> {Name,IsStatic,[Argument]} end, 
      Fields)).

bind_class_field_sets(NodeId,ClassName,FinalClassName,Fields) ->
  CompInfo =
    #comp_info
    {className=ClassName,
     node_id=NodeId,
     type=field_set,
     methodConstructor=
       fun (CName,Field,_,_Arguments) ->	
	   io_lib:format
	     ("java:field_set(NodeId,~p,~p)",
	      [CName,Field])
       end,
     methodFieldAccess=
       fun (N) -> {"set_fields",N} end,
     methodAccess=
       fun (IsStatic,_FormalParameters) ->
	   Argument =
	     if
	       IsStatic -> "null";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("~s,Value",
	      [Argument])
       end,
     genMethodFun=
       fun(Name,IsStatic,_FormalParameters,Body) ->
	   Argument =
	     if
	       IsStatic -> "NodeId";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("'set_~s'(~s,Value) ->~n  ~s~n~s",
	      [Name,
	       Argument,
	       io_lib:format
		 ("Class = java:class_info(~s,~p),",
		  [Argument,ClassName]),
	       Body])
       end,
     methodFun=
       fun(Name,_ParameterTypes,IsStatic,FormalParameters,Field,Accessor) ->
	   Argument =
	     if
	       IsStatic -> "NodeId";
	       true -> "Object"
	     end,
	   io_lib:format
	     ("field_set('~s',Value,~s) ->~n"++
		"  ~s~n"++
		"  Fun = ~s,~n"++
		"  Fun(~s)",
	      [Name,
	       Argument,
	       io_lib:format
		 ("Class = java:class_info(~s,~p),",
		  [Argument,ClassName]),
	       access_element(Field),
	       Accessor(IsStatic,FormalParameters)])
       end
    },
  translate_java_elements
    (CompInfo,
     lists:map
       (fun ({Name,IsStatic,Argument}) ->
	    {Name,IsStatic,[Argument]} 
	end, Fields)).

access_element({Accessor,N}) ->
  io_lib:format("element(~p,Class#class.~s)",[N,Accessor]).

translate_java_elements(CompInfo,Methods) ->
  {GeneratorCodes,GeneratorFuns,Accessors} =
    translate_elements(CompInfo,1,Methods),
  MethodMethods =
    count_args(Methods),
  NewGeneratorFuns =
    lists:foldl
  %% For each method name
      (fun ({Name,LengthMethods},Acc) ->
	   lists:foldl
	   %% For one arity of the given method
	     (fun ({Length,LenMethods},AccFuns) ->
		  {SignaturesAndCodes,IsStatic} =
		    lists:foldl
		      (fun ({Method={FName,StaticInfo,Parameters},Signature},
			    {AccF,AccIsStatic}) ->
			   case lists:keyfind({FName,Parameters},1,Accessors) of
			     {_,Accessor} ->
			       {[{Signature,Accessor}|AccF],
				StaticInfo orelse AccIsStatic};
			     false ->
			       io:format
				 ("No accessor for method ~p found??~n",
				  [Method]),
			       {AccF,StaticInfo orelse AccIsStatic}
			   end
		       end, {[],false}, LenMethods),
		  ?LOG("SignaturesAndCodes=~n~p~n",[SignaturesAndCodes]),
		  (gen_acc_fun
		   (Name,Length,LenMethods,SignaturesAndCodes,IsStatic,
		    CompInfo))++
		    AccFuns
	      end, Acc, LengthMethods);
	   (Other,_) ->
	   io:format("Got other value~n~p~n",[Other]),throw(bad)
       end, [],  MethodMethods),
  {GeneratorCodes,GeneratorFuns,NewGeneratorFuns}.

gen_acc_fun(Name,Length,LenMethods,SignaturesAndCodes,IsStatic,CompInfo) ->
  case SignaturesAndCodes of
    [] -> [];
    [{_,OneAccessor}|Rest] ->
      FormalParameters = n_parameters(Length),
      Body =
	if 
	  Rest==[] ->
	    io_lib:format
	      ("  (~s)(~s).~n",
	       [access_element(OneAccessor),
		(CompInfo#comp_info.methodAccess)
		(IsStatic,FormalParameters)]);
	  true ->
	    case lists:member(CompInfo#comp_info.type,[field_set,field_get]) of
	      true ->
		io:format
		  ("*** Warning: multiple access signatures"++
		   " for field operation~n~p~n "++
		   "SignaturesAndCodes=~n~p~nLen=~p,Methods=~n~p~n",
		   [Name,SignaturesAndCodes,Length,LenMethods]),
		io_lib:format
		  ("  (~s)(~s).~n",
		   [access_element(OneAccessor),
		    (CompInfo#comp_info.methodAccess)
		    (IsStatic,FormalParameters)]);
	      false ->
		emit_type_case
		  (CompInfo,SignaturesAndCodes,
		   FormalParameters,IsStatic)
	    end
	end,
      AccFun =
	(CompInfo#comp_info.genMethodFun)(Name,IsStatic,FormalParameters,Body),
      ?LOG("AccFun=~n~s~n",[AccFun]),
      [AccFun]
  end.
    
emit_type_case(CompInfo,Cases,FormalParameters,IsStatic) ->
  SortedCases =
    lists:sort
      (fun ({T1,_},{T2,_}) -> sort_types(CompInfo,T1,T2) end,
       Cases),
  Alternatives =
    lists:map
      (fun ({Type,Accessor}) ->
	   AccessCode =
	     io_lib:format
	       ("(~s)(~s)",
		[access_element(Accessor),
		 (CompInfo#comp_info.methodAccess)
		 (IsStatic,FormalParameters)]),
	   io_lib:format
	     ("    {~p,~n      fun () -> ~s end}",
	      [Type,AccessCode]);
	   (Other) ->
	   io:format("mismatch???~n~p~n",[Other]),
	   throw(bad)
       end, SortedCases),    
  io_lib:format
    ("  java:type_compatible_alternatives~n  "++
     "(Class#class.node,~n   [~s],~n   [~n~s]).\n",
     [print_comma_strings(FormalParameters),
      combine_strings(",\n",Alternatives)]).

normalize_type(int) -> primitive;
normalize_type(short) -> primitive;
normalize_type(long) -> primitive;
normalize_type(void) -> primitive;
normalize_type(byte) -> primitive;
normalize_type(double) -> primitive;
normalize_type(char) -> primitive;
normalize_type(float) -> primitive;
normalize_type(boolean) -> primitive;
normalize_type(Other) -> Other.

sort_types(CompInfo,Type1,Type2) ->
  T1 = normalize_type(Type1),
  T2 = normalize_type(Type2),
  case {T1,T2} of
    {T1l,T2l} when is_list(T1l), is_list(T2l) ->
      case length(T1l)==length(T2) of
	true ->
	  lists:foldl
	    (fun ({T1f,T2f},Value) ->
		 Value andalso sort_types(CompInfo,T1f,T2f)
	     end, true, lists:zip(T1l,T2l));
	false ->
	  true
      end;
    {primitive,_} ->
      true;
    {_,primitive} ->
      false;
    {{array,T3,D},{array,T4,D}} ->
      sort_types(CompInfo,T3,T4);
    {{array,_,_},_} ->
      true;
    {_,{array,_,_}} ->
      false;
    {Class1,Class2} when is_atom(Class1), is_atom(Class2) ->
      java:is_subtype(CompInfo#comp_info.node_id,Class1,Class2);
    _ ->
      true
  end.

translate_elements(_CompInfo,_N,[]) -> {[],[],[]};
translate_elements(CompInfo,N,[{Name,IsStatic,Parameters}|Rest]) ->
  %%io:format("Analysing ~p with ~p~n",[Name,Parameters]),
  {GeneratorCodeRest,GeneratorFunsRest,GeneratorAccessRest} =
    translate_elements(CompInfo,N+1,Rest),
  try translate_element(CompInfo,N,Name,IsStatic,Parameters) of
    {GeneratorCode, NewGeneratorFuns, GeneratorAccess} ->
      {[GeneratorCode|GeneratorCodeRest],
       NewGeneratorFuns++GeneratorFunsRest,
       [GeneratorAccess|GeneratorAccessRest]}
  catch _:nyi ->
      io:format("*** Warning: ~p with ~p not handled yet~n",[Name,Parameters]),
      {GeneratorCodeRest,GeneratorFunsRest,GeneratorAccessRest}
  end.

translate_element(CompInfo,N,Name,IsStatic,Parameters) ->
  ?LOG("binding method ~p:~p~n",[Name,Parameters]),
  ClassName = CompInfo#comp_info.className,
  GeneratorCode =
    io_lib:format
      ("~s",
       [gen_constr_fun
	(ClassName,Name,(CompInfo#comp_info.methodConstructor),
	 IsStatic,Parameters)]),
  FormalParameters = 
    n_parameters(length(Parameters)),
  GeneratorField = 
    (CompInfo#comp_info.methodFieldAccess)(N),
  GeneratorFun =
    (CompInfo#comp_info.methodFun)
      (Name,
       Parameters,
       IsStatic,
       FormalParameters,
       GeneratorField,
       CompInfo#comp_info.methodAccess),
  {GeneratorCode,
   [GeneratorFun],
   {{Name,Parameters},GeneratorField}}.

gen_constr_fun(ClassName,Name,MethodConstructor,IsStatic,Parameters) ->
  Return = MethodConstructor(ClassName,Name,IsStatic,Parameters),
  Return.

n_parameters(N) ->
  lists:map
    (fun (Num) -> "P"++integer_to_list(Num) end, lists:seq(1,N)).

indent(N) ->
  lists:duplicate(N,32).

count_args(Methods) ->
  lists:foldl
    (fun (Method={_Name,_,Parameters},NumMethods) ->
	 add_method
	   (Method,
	    typeof_parameters(Parameters),
	    length(Parameters),
	    NumMethods)
     end, [], Methods).

typeof_parameters(Parameters) ->
  lists:map (fun typeof_parameter/1, Parameters).

typeof_parameter(Parameter) ->
  case Parameter of
    'int' -> Parameter;
    'short' -> Parameter;
    'long' -> Parameter;
    'char' -> Parameter;
    'byte' -> Parameter;
    'double' -> Parameter;
    'void' -> Parameter;
    OtherAtom when is_atom(OtherAtom) -> OtherAtom;
    Other -> Other
  end.

add_method(Method={Name,_,_},Signature,Length,[]) ->
  [{Name,[{Length,[{Method,Signature}]}]}];
add_method(Method={Name,_,_},Signature,Length,[{Name1,Methods}|Rest]) ->
  if 
    Name==Name1 ->
      [{Name,
	add_method_with_length(Method,Signature,Length,Methods)}|Rest];
    true ->
      [{Name1,Methods}|add_method(Method,Signature,Length,Rest)]
  end.

add_method_with_length(Method,Signature,Length,[]) ->
  [{Length,[{Method,Signature}]}];
add_method_with_length(Method,Signature,Length,[{Length1,SMethods}|Rest]) ->
  if
    Length==Length1 ->
      [{Length,[{Method,Signature}|SMethods]}|Rest];
    true ->
      [{Length1,SMethods}|
       add_method_with_length(Method,Signature,Length,Rest)]
  end.


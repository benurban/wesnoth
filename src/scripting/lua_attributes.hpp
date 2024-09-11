/*
	Copyright (C) 2009 - 2024
	Part of the Battle for Wesnoth Project https://www.wesnoth.org/

	This program is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 2 of the License, or
	(at your option) any later version.
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY.

	See the COPYING file for more details.
*/

/// New attribute registration system, mainly for objects with a lot of attributes, like units
/// Not used for GUI2 widgets, as they're even more complicated with a deep hierarchy.

#pragma once

struct lua_State;
class t_string;
class vconfig;

#include "config.hpp"
#include "variable_info.hpp"
#include "map/location.hpp"

#include <string>
#include <string_view>
#include <vector>

struct luaW_Registry {
	inline static std::map<std::string_view /* metatable */, std::reference_wrapper<luaW_Registry>> lookup;
	using getters_list = std::map<std::string, std::function<bool(lua_State*,bool)>>;
	getters_list getters;
	using setters_list = std::map<std::string, std::function<bool(lua_State*,int,bool)>>;
	setters_list setters;
	std::string private_metatable;
	std::vector<std::string> public_metatable;
	luaW_Registry() = delete;
	luaW_Registry(const std::initializer_list<std::string>& mt);
	~luaW_Registry();
	int get(lua_State* L);
	int set(lua_State* L);
	int dir(lua_State* L);
};

template<typename object_type, typename value_type>
struct lua_getter
{
	virtual value_type get(lua_State* L, const object_type& obj) const = 0;
	virtual ~lua_getter() = default;
};

template<typename object_type, typename value_type>
struct lua_setter
{
	virtual void set(lua_State* L, object_type& obj, const value_type& value) const = 0;
	virtual ~lua_setter() = default;
};

template<typename T> struct lua_object_traits;

template<typename object_type, typename value_type, typename action_type, bool setter>
void register_lua_attribute(const char* name)
{
	using obj_traits = lua_object_traits<object_type>;
	using map_type = std::conditional_t<setter, luaW_Registry::setters_list, luaW_Registry::getters_list>;
	using callback_type = typename map_type::mapped_type;
	map_type* map;
	callback_type fcn;
	if constexpr(setter) {
		map = &luaW_Registry::lookup.at(obj_traits::metatable).get().setters;
		fcn = [action = action_type()](lua_State* L, int idx, bool nop) {
			if(nop) return true;
			decltype(auto) obj = obj_traits::get(L, 1);
			action.set(L, obj, lua_check<value_type>(L, idx));
			return true;
		};
	} else {
		map = &luaW_Registry::lookup.at(obj_traits::metatable).get().getters;
		fcn = [action = action_type()](lua_State* L, bool nop) {
			if(nop) return true;
			lua_push(L, action.get(L, obj_traits::get(L, 1)));
			return true;
		};
	}
	(*map)[std::string(name)] = fcn;
}

#define LATTR_GETTER5(name, value_type, obj_type, obj_name, id) \
struct BOOST_PP_CAT(getter_, id) : public lua_getter<obj_type, value_type> { \
	using object_type = obj_type; \
	virtual value_type get(lua_State* L, const object_type& obj_name) const override; \
}; \
struct BOOST_PP_CAT(getter_adder_, id) { \
	BOOST_PP_CAT(getter_adder_, id) () \
	{ \
		register_lua_attribute<obj_type, value_type, BOOST_PP_CAT(getter_, id), false>(name); \
	} \
}; \
static BOOST_PP_CAT(getter_adder_, id) BOOST_PP_CAT(getter_adder_instance_, id) ; \
value_type BOOST_PP_CAT(getter_, id)::get([[maybe_unused]] lua_State* L, const BOOST_PP_CAT(getter_, id)::object_type& obj_name) const


#define LATTR_SETTER5(name, value_type, obj_type, obj_name, id) \
struct BOOST_PP_CAT(setter_, id) : public lua_setter<obj_type, value_type> { \
	using object_type = obj_type; \
	void set(lua_State* L, object_type& obj_name, const value_type& value) const override; \
}; \
struct BOOST_PP_CAT(setter_adder_, id) { \
	BOOST_PP_CAT(setter_adder_, id) ()\
	{ \
		register_lua_attribute<obj_type, value_type, BOOST_PP_CAT(setter_, id), true>(name); \
	} \
}; \
static BOOST_PP_CAT(setter_adder_, id) BOOST_PP_CAT(setter_adder_instance_, id); \
void BOOST_PP_CAT(setter_, id)::set([[maybe_unused]] lua_State* L, BOOST_PP_CAT(setter_, id)::object_type& obj_name, const value_type& value) const


/**
 * @param name: string  attribute name
 * @param value_type: the type of the attribute, for example int or std::string
 * @param obj_type: the type of the object, for example lua_unit
 * @param metatable: the metatable name for the object
 */
#define LATTR_GETTER(name, value_type, obj_type, obj_name) LATTR_GETTER5(name, value_type, obj_type, obj_name, __LINE__)

#define LATTR_SETTER(name, value_type, obj_type, obj_name) LATTR_SETTER5(name, value_type, obj_type, obj_name, __LINE__)

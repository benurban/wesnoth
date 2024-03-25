/*
	Copyright (C) 2003 - 2024
	by David White <dave@whitevine.net>
	Part of the Battle for Wesnoth Project https://www.wesnoth.org/

	This program is free software; you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation; either version 2 of the License, or
	(at your option) any later version.
	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY.

	See the COPYING file for more details.
*/

#pragma once

#include "tstring.hpp"
#include "serialization/string_utils.hpp"


class game_config_view;

//this module controls internationalization.


struct language_def
{
	language_def() :
		localename(),
		alternates(),
		language(),
		sort_name(),
		rtl(false),
		percent(100)
		{}

	language_def(const std::string& name, const t_string& lang, const std::string& dir,
	             const std::string &salternates = "", const std::string& sort_name = "", const std::string& percent = "100") :
		localename(name),
		alternates(utils::split(salternates)),
		language(lang),
		sort_name(sort_name.empty() ? std::string(lang) : sort_name),
		rtl(dir == "rtl")
	{
		try {
			this->percent = percent.empty() ? 100 : std::stoi(percent);
		} catch(const std::invalid_argument&) {
			this->percent = 100;
		}
	}

	std::string localename;
	std::vector<std::string> alternates;
	t_string language;
	std::string sort_name;
	bool rtl;		// A right to left language? (e.g: Hebrew)
	/** % of translated text in core po-s */
	int percent;
	bool operator== (const language_def&) const;
	bool operator< (const language_def& a) const
		{ return sort_name < a.sort_name; }
};

typedef std::vector<language_def> language_list;

struct symbol_table
{
	/**
	 * Look up the string mappings given in [language] tags. If the key is not
	 * found, fall back to returning a string that's only meant for developers
	 * to see.
	 */
	const t_string& operator[](const std::string& key) const;
	const t_string& operator[](const char* key) const;
	/**
	 * Look up the string mappings given in [language] tags. If the key is not
	 * found, returns symbol_table::end().
	 */
	utils::string_map::const_iterator find(const std::string& key) const;
	utils::string_map::const_iterator end() const;
};

//table of strings which are displayed to the user. Maps ids -> text.
//this table should be consulted whenever something is to be
//displayed on screen.
extern symbol_table string_table;

bool& time_locale_correct();

/**
 * Return a list of available translations.
 *
 * The list will normally be filtered with incomplete (according to
 * min_translation_percent) translations removed.
 *
 *@param all if true, include incomplete translations
 *@pre load_language_list() has already been called
 */
std::vector<language_def> get_languages(bool all=false);

//function which, given the main configuration object, and a locale,
//will set string_table to be populated with data from that locale.
//locale may be either the full name of the language, like 'English',
//or the 2-letter version, like 'en'.
void set_language(const language_def& locale);

//function which returns the name of the language currently used
const language_def& get_language();
bool current_language_rtl();

//function which attempts to query and return the locale on the system
const language_def& get_locale();

/** Initializes the list of textdomains from a configuration object */
void init_textdomains(const game_config_view& cfg);

/** Initializes certain English strings */
bool init_strings(const game_config_view& cfg);

bool load_language_list();

void set_min_translation_percent(int percent);

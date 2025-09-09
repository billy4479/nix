{ pkgs, ... }:
{
  programs.neovim.plugins = with pkgs.vimPlugins; [
    {
      plugin = luasnip;
      type = "lua";
      config = # lua
        ''
          local ls = require("luasnip")
          ls.setup()

          local s = ls.snippet
          local sn = ls.snippet_node
          local isn = ls.indent_snippet_node
          local t = ls.text_node
          local i = ls.insert_node
          local f = ls.function_node
          local c = ls.choice_node
          local d = ls.dynamic_node
          local r = ls.restore_node
          -- local events = require("luasnip.util.events")
          -- local ai = require("luasnip.nodes.absolute_indexer")
          -- local extras = require("luasnip.extras")
          -- local l = extras.lambda
          -- local rep = extras.rep
          -- local p = extras.partial
          -- local m = extras.match
          -- local n = extras.nonempty
          -- local dl = extras.dynamic_lambda
          -- local fmt = require("luasnip.extras.fmt").fmt
          -- local fmta = require("luasnip.extras.fmt").fmta
          -- local conds = require("luasnip.extras.expand_conditions")
          -- local postfix = require("luasnip.extras.postfix").postfix
          -- local types = require("luasnip.util.types")
          -- local parse = require("luasnip.util.parser").parse_snippet
          -- local ms = ls.multi_snippet
          -- local k = require("luasnip.nodes.key_indexer").new_key

          local function to_label_name(args)
          	return args[1][1]:lower():gsub(" ", "-"):gsub("%$", "")
          end

          local function thm_env(trig, name)
          	return s(trig, {
          		t("\\begin{" .. name .. "}{"),
          		i(1),
          		t("}{"),
          		f(to_label_name, { 1 }, {}),
          		t({ "}", "\t" }),
          		i(2),
          		t({ "", "\\end{" .. name .. "}", "" }),
          	})
          end

          local function generic_env(trig, name)
          	return s(trig, {
          		t({ "\\begin{" .. name .. "}", "\t" }),
          		i(1),
          		t({ "", "\\end{" .. name .. "}", "" }),
          		i(0),
          	})
          end

          local function generic_command(trig, name)
          	return s(trig, {
          		t("\\" .. name .. "{"),
          		i(1),
          		t("} "),
          		i(0),
          	})
          end

          local function generic_up_down(trig, name)
          	return s(trig, {
          		t("\\" .. name .. "_{"),
          		i(1),
          		t("}^{"),
          		i(2),
          		t("} "),
          		i(0),
          	})
          end

          local function figure(trig, name)
          	return s(trig, {
          		t("\\begin{figure}["),
          		i(3, "!ht"),
          		t({ "]", "\t\\centering", "\t" }),
          		d(1, function(args, parent, old_state, user_args)
          			if name == "" then
          				return sn(nil, i(1))
          			else
          				return sn(nil, {
          					t("\\include" .. name .. "[width="),
          					i(2, "0.5"),
          					t("\\textwidth]{"),
          					i(1),
          					t({ "}", "\t\\caption{" }),
          					i(3),
          					t("}"),
          				})
          			end
          		end, {}),
          		t({ "", "\\end{figure}", "" }),
          		i(0),
          	})
          end

          ls.add_snippets("tex", {
          	generic_env("eq", "equation"),
          	generic_env("al", "align"),
          	generic_env("mat", "pmatrix"),
          	generic_env("pr", "proof"),

          	generic_command("cal", "mathcal"),
          	generic_command("ds", "mathds"),
          	generic_command("emph", "emph"),
          	generic_command("bf", "textbf"),
          	generic_command("it", "textit"),

          	generic_up_down("int", "int"),
          	generic_up_down("sum", "sum"),
          	generic_up_down("union", "bigcup"),
          	generic_up_down("inter", "bigcap"),

          	thm_env("def", "definition"),
          	thm_env("thm", "theorem"),
          	thm_env("prop", "proposition"),
          	thm_env("lemma", "lemma"),
          	thm_env("cor", "corollary"),
          	thm_env("rm", "remark"),

          	figure("fig", ""),
          	figure("img", "graphics"),
          	figure("svg", "svg"),
          })
        '';
    }
  ];
}

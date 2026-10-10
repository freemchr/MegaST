---------------------------------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65 (MegaST)
--
-- MEGA65 keyboard to Atari ST keyboard matrix
--
-- Runs in the clock domain of the core.
--
-- The Atari ST keyboard is scanned by the IKBD (HD6301) as a 15 x 8 matrix. This module creates
-- the low active matrix (index = column * 8 + row) directly from the MEGA65 keyboard, so that the
-- real IKBD firmware sees real key presses (including multiple simultaneous keys).
--
-- The mapping is positional where the MEGA65 (C64 style) layout differs from the ST layout:
--
--    MEGA65            Atari ST             MEGA65            Atari ST
--    ---------------------------------      ---------------------------------
--    Esc               Esc                  Inst/Del          Backspace
--    Tab               Tab                  Arrow up (^)      Delete
--    Ctrl              Control              No Scroll         Insert
--    Alt               Alternate            Clr/Home          Clr/Home
--    Caps Lock         Caps Lock            Run/Stop          Undo
--    F1/F3/F5/F7/F9    F1/F3/F5/F7/F9       F11               Undo
--    Shift+F1..F9      F2/F4/F6/F8/F10      F13               Help
--    MEGA+F1..F9       Shift+F1/F3/../F9    MEGA+Shift+F1..F9 Shift+F2/F4/../F10 (F11..F20 in GFA-Basic, STOS)
--    + - Pound         - = \                Arrow left        `
--    @ *               [ ]                  : ; =             ; ' ISO(<>)
--    Cursor keys       Cursor keys
--
-- Numeric keypad: the MEGA65 has none, so while the MEGA key is held down, these keys are keypad keys:
--
--    MEGA + 0..9       Keypad 0..9          MEGA + Return     Keypad Enter
--    MEGA + + - * /    Keypad + - * /       MEGA + .          Keypad .
--    MEGA + ( )        Keypad ( )           (MEGA + Shift + 8 / 9, as printed on the MEGA65)
--
-- The MEGA65 Help key opens the M2M on-screen-menu and is therefore not mapped.
--
-- Menu Keyboard "as printed" (as_printed_i): digits and symbols give the character printed on the MEGA65
-- key, for the US or the UK ST layout (uk_i: the language of the TOS). The core presses or hides the ST's
-- Shift key as needed, e.g. MEGA65 Shift+2 is ST Shift+' (US) or Shift+2 (UK), MEGA65 + is ST Shift+=.
-- Keys without a shifted symbol on the MEGA65 give the same character with Shift. Extra characters that
-- are not printed on the MEGA65 keys:
--
--    Shift + :  [          Shift + @  {          Pound      \          Arrow left           `
--    Shift + ;  ]          Shift + *  }          Shift + -  _          Shift + Arrow left   ~
--    Shift + Pound  |
--
-- When the Shift state that the ST sees has to change, the symbol key (and F1..F10) follows C_SETTLE later, so that the
-- IKBD never sees the symbol key together with the wrong Shift state.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
-- This machine is based on AtariST_MiSTer
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
---------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity keyboard is
   generic (
      G_CLK_SPEED          : natural                     -- clock speed of clk_main_i in Hz
   );
   port (
      clk_main_i           : in std_logic;               -- core clock

      -- Interface to the MEGA65 keyboard
      key_num_i            : in integer range 0 to 79;   -- cycles through all MEGA65 keys
      key_pressed_n_i      : in std_logic;               -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- Menu: digits and symbols as printed on the MEGA65 keys (else positional)
      as_printed_i         : in std_logic := '0';
      uk_i                 : in std_logic := '0';      -- "as printed" for a UK TOS (else US)

      -- Atari ST keyboard matrix: low active, index = column * 8 + row
      st_matrix_n_o        : out std_logic_vector(119 downto 0)
   );
end keyboard;

architecture beh of keyboard is

-- MEGA65 key codes that kb_key_num_i is using while
-- kb_key_pressed_n_i is signalling (low active) which key is pressed
constant m65_ins_del       : integer := 0;
constant m65_return        : integer := 1;
constant m65_horz_crsr     : integer := 2;   -- means cursor right in C64 terminology
constant m65_f7            : integer := 3;
constant m65_f1            : integer := 4;
constant m65_f3            : integer := 5;
constant m65_f5            : integer := 6;
constant m65_vert_crsr     : integer := 7;   -- means cursor down in C64 terminology
constant m65_3             : integer := 8;
constant m65_w             : integer := 9;
constant m65_a             : integer := 10;
constant m65_4             : integer := 11;
constant m65_z             : integer := 12;
constant m65_s             : integer := 13;
constant m65_e             : integer := 14;
constant m65_left_shift    : integer := 15;
constant m65_5             : integer := 16;
constant m65_r             : integer := 17;
constant m65_d             : integer := 18;
constant m65_6             : integer := 19;
constant m65_c             : integer := 20;
constant m65_f             : integer := 21;
constant m65_t             : integer := 22;
constant m65_x             : integer := 23;
constant m65_7             : integer := 24;
constant m65_y             : integer := 25;
constant m65_g             : integer := 26;
constant m65_8             : integer := 27;
constant m65_b             : integer := 28;
constant m65_h             : integer := 29;
constant m65_u             : integer := 30;
constant m65_v             : integer := 31;
constant m65_9             : integer := 32;
constant m65_i             : integer := 33;
constant m65_j             : integer := 34;
constant m65_0             : integer := 35;
constant m65_m             : integer := 36;
constant m65_k             : integer := 37;
constant m65_o             : integer := 38;
constant m65_n             : integer := 39;
constant m65_plus          : integer := 40;
constant m65_p             : integer := 41;
constant m65_l             : integer := 42;
constant m65_minus         : integer := 43;
constant m65_dot           : integer := 44;
constant m65_colon         : integer := 45;
constant m65_at            : integer := 46;
constant m65_comma         : integer := 47;
constant m65_gbp           : integer := 48;
constant m65_asterisk      : integer := 49;
constant m65_semicolon     : integer := 50;
constant m65_clr_home      : integer := 51;
constant m65_right_shift   : integer := 52;
constant m65_equal         : integer := 53;
constant m65_arrow_up      : integer := 54;  -- symbol, not cursor
constant m65_slash         : integer := 55;
constant m65_1             : integer := 56;
constant m65_arrow_left    : integer := 57;  -- symbol, not cursor
constant m65_ctrl          : integer := 58;
constant m65_2             : integer := 59;
constant m65_space         : integer := 60;
constant m65_mega          : integer := 61;
constant m65_q             : integer := 62;
constant m65_run_stop      : integer := 63;
constant m65_no_scrl       : integer := 64;
constant m65_tab           : integer := 65;
constant m65_alt           : integer := 66;
constant m65_help          : integer := 67;
constant m65_f9            : integer := 68;
constant m65_f11           : integer := 69;
constant m65_f13           : integer := 70;
constant m65_esc           : integer := 71;
constant m65_capslock      : integer := 72;
constant m65_up_crsr       : integer := 73;  -- cursor up
constant m65_left_crsr     : integer := 74;  -- cursor left
constant m65_restore       : integer := 75;

-- Atari ST keyboard matrix positions: column * 8 + row (see AtariST_MiSTer/rtl/ikbd/ps2.sv)
function st(col : natural; row : natural) return natural is
begin
   return col * 8 + row;
end function st;

constant st_a        : natural := st( 4, 5);
constant st_b        : natural := st( 7, 6);
constant st_c        : natural := st( 6, 6);
constant st_d        : natural := st( 5, 6);
constant st_e        : natural := st( 5, 4);
constant st_f        : natural := st( 6, 5);
constant st_g        : natural := st( 7, 4);
constant st_h        : natural := st( 7, 5);
constant st_i        : natural := st( 8, 4);
constant st_j        : natural := st( 8, 5);
constant st_k        : natural := st( 8, 6);
constant st_l        : natural := st( 9, 5);
constant st_m        : natural := st( 8, 7);
constant st_n        : natural := st( 7, 7);
constant st_o        : natural := st( 9, 3);
constant st_p        : natural := st( 9, 4);
constant st_q        : natural := st( 4, 4);
constant st_r        : natural := st( 6, 3);
constant st_s        : natural := st( 5, 5);
constant st_t        : natural := st( 6, 4);
constant st_u        : natural := st( 8, 3);
constant st_v        : natural := st( 6, 7);
constant st_w        : natural := st( 5, 3);
constant st_x        : natural := st( 5, 7);
constant st_y        : natural := st( 7, 3);
constant st_z        : natural := st( 4, 7);
constant st_1        : natural := st( 4, 2);
constant st_2        : natural := st( 5, 1);
constant st_3        : natural := st( 5, 2);
constant st_4        : natural := st( 6, 1);
constant st_5        : natural := st( 6, 2);
constant st_6        : natural := st( 7, 1);
constant st_7        : natural := st( 7, 2);
constant st_8        : natural := st( 8, 1);
constant st_9        : natural := st( 8, 2);
constant st_0        : natural := st( 9, 1);
constant st_f1       : natural := st( 1, 0);
constant st_f2       : natural := st( 2, 0);
constant st_f3       : natural := st( 3, 0);
constant st_f4       : natural := st( 4, 0);
constant st_f5       : natural := st( 5, 0);
constant st_f6       : natural := st( 6, 0);
constant st_f7       : natural := st( 7, 0);
constant st_f8       : natural := st( 8, 0);
constant st_f9       : natural := st( 9, 0);
constant st_f10      : natural := st(10, 0);
constant st_return   : natural := st(11, 5);
constant st_space    : natural := st( 9, 7);
constant st_esc      : natural := st( 4, 1);
constant st_bs       : natural := st(11, 1);
constant st_tab      : natural := st( 4, 3);
constant st_grave    : natural := st(10, 2);  -- ` ~
constant st_minus    : natural := st( 9, 2);  -- - _
constant st_equal    : natural := st(10, 1);  -- = +
constant st_lbracket : natural := st(10, 3);  -- [ {
constant st_rbracket : natural := st(10, 4);  -- ] }
constant st_bslash   : natural := st(11, 4);  -- \ |
constant st_semicol  : natural := st(10, 5);  -- ; :
constant st_quote    : natural := st(11, 6);  -- ' "
constant st_comma    : natural := st( 9, 6);  -- , <
constant st_dot      : natural := st(10, 6);  -- . >
constant st_slash    : natural := st(11, 7);  -- / ?
constant st_iso      : natural := st( 4, 6);  -- ISO key (< > on european keyboards)
constant st_lshift   : natural := st( 1, 5);
constant st_rshift   : natural := st( 3, 7);
constant st_alt      : natural := st( 2, 6);
constant st_ctrl     : natural := st( 0, 4);
constant st_caps     : natural := st(10, 7);
constant st_up       : natural := st(12, 1);
constant st_down     : natural := st(12, 4);
constant st_left     : natural := st(12, 3);
constant st_right    : natural := st(12, 5);
constant st_insert   : natural := st(11, 3);
constant st_home     : natural := st(12, 2);
constant st_help     : natural := st(11, 0);
constant st_delete   : natural := st(11, 2);
constant st_undo     : natural := st(12, 0);
constant st_kp_lpar  : natural := st(13, 0);  -- keypad (
constant st_kp_rpar  : natural := st(13, 1);  -- keypad )
constant st_kp_slash : natural := st(14, 0);
constant st_kp_star  : natural := st(14, 1);
constant st_kp_7     : natural := st(13, 2);
constant st_kp_8     : natural := st(13, 3);
constant st_kp_9     : natural := st(14, 2);
constant st_kp_minus : natural := st(14, 3);
constant st_kp_4     : natural := st(13, 4);
constant st_kp_5     : natural := st(13, 5);
constant st_kp_6     : natural := st(14, 4);
constant st_kp_plus  : natural := st(14, 5);
constant st_kp_1     : natural := st(12, 6);
constant st_kp_2     : natural := st(13, 6);
constant st_kp_3     : natural := st(14, 6);
constant st_kp_0     : natural := st(12, 7);
constant st_kp_dot   : natural := st(13, 7);
constant st_kp_enter : natural := st(14, 7);

-- Length of the Caps Lock key press that is generated when the (latching) MEGA65 Caps Lock key changes
constant C_CAPS_PULSE : natural := G_CLK_SPEED / 20;  -- 50 ms

signal key_pressed_n : std_logic_vector(79 downto 0) := (others => '1');

-- "Keyboard as printed": delay of a symbol key after the Shift state of the ST changed
constant C_SETTLE     : natural := G_CLK_SPEED / 50;  -- 20 ms

signal caps_state    : std_logic := '1';
signal caps_counter  : natural range 0 to C_CAPS_PULSE := 0;

signal st_shift_d    : boolean := false;
signal settle_cnt    : natural range 0 to C_SETTLE := 0;

begin

   keyboard_state : process(clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         key_pressed_n(key_num_i) <= key_pressed_n_i;
      end if;
   end process keyboard_state;

   -- The MEGA65 Caps Lock key is a latching key, while the ST's Caps Lock key is a normal key that
   -- is toggled by TOS: Generate a short key press whenever the state of the MEGA65 key changes.
   caps_lock : process(clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         caps_state <= key_pressed_n(m65_capslock);
         if caps_state /= key_pressed_n(m65_capslock) then
            caps_counter <= C_CAPS_PULSE;
         elsif caps_counter /= 0 then
            caps_counter <= caps_counter - 1;
         end if;
      end if;
   end process caps_lock;

   matrix : process(clk_main_i)
      variable m        : std_logic_vector(119 downto 0);
      variable shift    : boolean;
      variable fshift   : boolean;
      variable fkey     : boolean;
      variable mfkey    : boolean;
      variable keypad   : boolean;
      variable printed  : boolean;
      variable sym      : std_logic_vector(119 downto 0);   -- symbol keys of the "as printed" mapping
      variable want_on  : boolean;                          -- a pressed symbol needs Shift
      variable want_off : boolean;                          -- a pressed symbol needs no Shift
      variable st_shift : boolean;
      variable uk       : boolean;

      -- ST key (col, row) is pressed while the MEGA65 key is pressed.
      -- The matrix and the key state are explicit parameters: Vivado (2026.1) turns the first call of a
      -- procedure that writes the process variable m implicitly into a constant (key always pressed).
      procedure map_key(variable mx : inout std_logic_vector(119 downto 0); m65_n : std_logic; atari : natural) is
      begin
         if m65_n = '0' then
            mx(atari) := '0';
         end if;
      end procedure map_key;

      -- "As printed": ST key atari with (sh = true) or without Shift is pressed while the MEGA65 key is pressed
      procedure map_sym(variable mx : inout std_logic_vector(119 downto 0); variable on_v, off_v : inout boolean;
                        m65_n : std_logic; atari : natural; sh : boolean) is
      begin
         if m65_n = '0' then
            mx(atari) := '0';
            if sh then on_v := true; else off_v := true; end if;
         end if;
      end procedure map_sym;

   begin
      if rising_edge(clk_main_i) then
         m      := (others => '1');
         shift  := key_pressed_n(m65_left_shift) = '0' or key_pressed_n(m65_right_shift) = '0';
         keypad := key_pressed_n(m65_mega) = '0';
         printed := as_printed_i = '1' and not keypad;
         uk      := uk_i = '1';
         sym      := (others => '1');
         want_on  := false;
         want_off := false;

         -- Shift + F1/F3/F5/F7/F9 means F2/F4/F6/F8/F10 (as printed on the MEGA65 keyboard):
         -- in this case the ST does not see the shift key
         fkey   := key_pressed_n(m65_f1) = '0' or key_pressed_n(m65_f3) = '0' or key_pressed_n(m65_f5) = '0' or
                   key_pressed_n(m65_f7) = '0' or key_pressed_n(m65_f9) = '0';
         fshift := shift and fkey;
         -- MEGA + function key: the ST sees Shift + function key (F11..F20 in GFA-Basic and STOS, issue #18)
         mfkey  := keypad and fkey;

         -- letters
         map_key(m, key_pressed_n(m65_a), st_a);   map_key(m, key_pressed_n(m65_b), st_b);   map_key(m, key_pressed_n(m65_c), st_c);   map_key(m, key_pressed_n(m65_d), st_d);
         map_key(m, key_pressed_n(m65_e), st_e);   map_key(m, key_pressed_n(m65_f), st_f);   map_key(m, key_pressed_n(m65_g), st_g);   map_key(m, key_pressed_n(m65_h), st_h);
         map_key(m, key_pressed_n(m65_i), st_i);   map_key(m, key_pressed_n(m65_j), st_j);   map_key(m, key_pressed_n(m65_k), st_k);   map_key(m, key_pressed_n(m65_l), st_l);
         map_key(m, key_pressed_n(m65_m), st_m);   map_key(m, key_pressed_n(m65_n), st_n);   map_key(m, key_pressed_n(m65_o), st_o);   map_key(m, key_pressed_n(m65_p), st_p);
         map_key(m, key_pressed_n(m65_q), st_q);   map_key(m, key_pressed_n(m65_r), st_r);   map_key(m, key_pressed_n(m65_s), st_s);   map_key(m, key_pressed_n(m65_t), st_t);
         map_key(m, key_pressed_n(m65_u), st_u);   map_key(m, key_pressed_n(m65_v), st_v);   map_key(m, key_pressed_n(m65_w), st_w);   map_key(m, key_pressed_n(m65_x), st_x);
         map_key(m, key_pressed_n(m65_y), st_y);   map_key(m, key_pressed_n(m65_z), st_z);

         -- digits, or the numeric keypad while the MEGA key is held down
         if keypad then
            map_key(m, key_pressed_n(m65_1), st_kp_1);   map_key(m, key_pressed_n(m65_2), st_kp_2);   map_key(m, key_pressed_n(m65_3), st_kp_3);
            map_key(m, key_pressed_n(m65_4), st_kp_4);   map_key(m, key_pressed_n(m65_5), st_kp_5);   map_key(m, key_pressed_n(m65_6), st_kp_6);
            map_key(m, key_pressed_n(m65_7), st_kp_7);   map_key(m, key_pressed_n(m65_0), st_kp_0);
            -- MEGA + Shift + 8 / 9 = ( ) as printed on the MEGA65
            if shift then
               map_key(m, key_pressed_n(m65_8), st_kp_lpar);   map_key(m, key_pressed_n(m65_9), st_kp_rpar);
            else
               map_key(m, key_pressed_n(m65_8), st_kp_8);      map_key(m, key_pressed_n(m65_9), st_kp_9);
            end if;
            map_key(m, key_pressed_n(m65_plus), st_kp_plus);
            map_key(m, key_pressed_n(m65_minus), st_kp_minus);
            map_key(m, key_pressed_n(m65_asterisk), st_kp_star);
            map_key(m, key_pressed_n(m65_slash), st_kp_slash);
            map_key(m, key_pressed_n(m65_dot), st_kp_dot);
            map_key(m, key_pressed_n(m65_return), st_kp_enter);
         elsif printed then
            if shift then   -- ! " # $ % & ' ( ) 0
               map_sym(sym, want_on, want_off, key_pressed_n(m65_1), st_1,     true);
               if uk then   -- UK ST: " is Shift+2, # has its own key (US \ position)
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_2), st_2,      true);
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_3), st_bslash, false);
               else
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_2), st_quote,  true);
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_3), st_3,      true);
               end if;
               map_sym(sym, want_on, want_off, key_pressed_n(m65_4), st_4,     true);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_5), st_5,     true);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_6), st_7,     true);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_7), st_quote, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_8), st_9,     true);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_9), st_0,     true);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_0), st_0,     false);
            else
               map_sym(sym, want_on, want_off, key_pressed_n(m65_1), st_1, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_2), st_2, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_3), st_3, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_4), st_4, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_5), st_5, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_6), st_6, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_7), st_7, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_8), st_8, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_9), st_9, false);
               map_sym(sym, want_on, want_off, key_pressed_n(m65_0), st_0, false);
            end if;
         else
            map_key(m, key_pressed_n(m65_1), st_1);   map_key(m, key_pressed_n(m65_2), st_2);   map_key(m, key_pressed_n(m65_3), st_3);   map_key(m, key_pressed_n(m65_4), st_4);
            map_key(m, key_pressed_n(m65_5), st_5);   map_key(m, key_pressed_n(m65_6), st_6);   map_key(m, key_pressed_n(m65_7), st_7);   map_key(m, key_pressed_n(m65_8), st_8);
            map_key(m, key_pressed_n(m65_9), st_9);   map_key(m, key_pressed_n(m65_0), st_0);
         end if;

         -- function keys: like the symbol keys, they follow C_SETTLE after a change of the ST's Shift
         -- state, otherwise the IKBD can see F6 (Shift+F5 on the MEGA65) while Shift is still pressed
         -- and reports Shift+F6 (issue #16)
         if fshift then
            map_key(sym, key_pressed_n(m65_f1), st_f2);
            map_key(sym, key_pressed_n(m65_f3), st_f4);
            map_key(sym, key_pressed_n(m65_f5), st_f6);
            map_key(sym, key_pressed_n(m65_f7), st_f8);
            map_key(sym, key_pressed_n(m65_f9), st_f10);
         else
            map_key(sym, key_pressed_n(m65_f1), st_f1);
            map_key(sym, key_pressed_n(m65_f3), st_f3);
            map_key(sym, key_pressed_n(m65_f5), st_f5);
            map_key(sym, key_pressed_n(m65_f7), st_f7);
            map_key(sym, key_pressed_n(m65_f9), st_f9);
         end if;
         map_key(m, key_pressed_n(m65_f11), st_undo);
         map_key(m, key_pressed_n(m65_f13), st_help);

         -- special keys
         if not keypad then
            map_key(m, key_pressed_n(m65_return), st_return);
         end if;
         map_key(m, key_pressed_n(m65_space), st_space);
         map_key(m, key_pressed_n(m65_esc), st_esc);
         map_key(m, key_pressed_n(m65_ins_del), st_bs);
         map_key(m, key_pressed_n(m65_tab), st_tab);
         map_key(m, key_pressed_n(m65_arrow_up), st_delete);
         map_key(m, key_pressed_n(m65_no_scrl), st_insert);
         map_key(m, key_pressed_n(m65_clr_home), st_home);
         map_key(m, key_pressed_n(m65_run_stop), st_undo);

         -- symbols as printed on the MEGA65 keys
         if printed then
            if shift then
               map_sym(sym, want_on, want_off, key_pressed_n(m65_plus),       st_equal,    false);  -- +
               map_sym(sym, want_on, want_off, key_pressed_n(m65_minus),      st_minus,    true);   -- _
               if uk then   -- UK ST: \ | on the ISO key, # ~ on the US \ key
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_gbp),        st_iso,      true);   -- |
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_arrow_left), st_bslash,   true);   -- ~
               else
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_gbp),        st_bslash,   true);   -- |
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_arrow_left), st_grave,    true);   -- ~
               end if;
               map_sym(sym, want_on, want_off, key_pressed_n(m65_at),         st_lbracket, true);   -- {
               map_sym(sym, want_on, want_off, key_pressed_n(m65_asterisk),   st_rbracket, true);   -- }
               map_sym(sym, want_on, want_off, key_pressed_n(m65_arrow_up),   st_6,        true);   -- ^
               map_sym(sym, want_on, want_off, key_pressed_n(m65_colon),      st_lbracket, false);  -- [
               map_sym(sym, want_on, want_off, key_pressed_n(m65_semicolon),  st_rbracket, false);  -- ]
               map_sym(sym, want_on, want_off, key_pressed_n(m65_equal),      st_equal,    false);  -- =
               map_sym(sym, want_on, want_off, key_pressed_n(m65_comma),      st_comma,    true);   -- <
               map_sym(sym, want_on, want_off, key_pressed_n(m65_dot),        st_dot,      true);   -- >
               map_sym(sym, want_on, want_off, key_pressed_n(m65_slash),      st_slash,    true);   -- ?
            else
               map_sym(sym, want_on, want_off, key_pressed_n(m65_plus),       st_equal,    true);   -- +
               map_sym(sym, want_on, want_off, key_pressed_n(m65_minus),      st_minus,    false);  -- -
               if uk then   -- UK ST: \ on the ISO key, @ is Shift+'
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_gbp),     st_iso,      false);  -- \
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_at),      st_quote,    true);   -- @
               else
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_gbp),     st_bslash,   false);  -- \
                  map_sym(sym, want_on, want_off, key_pressed_n(m65_at),      st_2,        true);   -- @
               end if;
               map_sym(sym, want_on, want_off, key_pressed_n(m65_asterisk),   st_8,        true);   -- *
               map_sym(sym, want_on, want_off, key_pressed_n(m65_arrow_up),   st_6,        true);   -- ^
               map_sym(sym, want_on, want_off, key_pressed_n(m65_colon),      st_semicol,  true);   -- :
               map_sym(sym, want_on, want_off, key_pressed_n(m65_semicolon),  st_semicol,  false);  -- ;
               map_sym(sym, want_on, want_off, key_pressed_n(m65_equal),      st_equal,    false);  -- =
               map_sym(sym, want_on, want_off, key_pressed_n(m65_comma),      st_comma,    false);  -- ,
               map_sym(sym, want_on, want_off, key_pressed_n(m65_dot),        st_dot,      false);  -- .
               map_sym(sym, want_on, want_off, key_pressed_n(m65_slash),      st_slash,    false);  -- /
               map_sym(sym, want_on, want_off, key_pressed_n(m65_arrow_left), st_grave,    false);  -- `
            end if;
         end if;

         -- symbols (positional mapping)
         if not printed and not keypad then
            map_key(m, key_pressed_n(m65_plus), st_minus);
            map_key(m, key_pressed_n(m65_minus), st_equal);
            map_key(m, key_pressed_n(m65_asterisk), st_rbracket);
            map_key(m, key_pressed_n(m65_dot), st_dot);
            map_key(m, key_pressed_n(m65_slash), st_slash);
         end if;
         if not printed then
            map_key(m, key_pressed_n(m65_gbp), st_bslash);
            map_key(m, key_pressed_n(m65_arrow_left), st_grave);
            map_key(m, key_pressed_n(m65_at), st_lbracket);
            map_key(m, key_pressed_n(m65_colon), st_semicol);
            map_key(m, key_pressed_n(m65_semicolon), st_quote);
            map_key(m, key_pressed_n(m65_equal), st_iso);
            map_key(m, key_pressed_n(m65_comma), st_comma);
         end if;

         -- modifiers (MEGA + Shift + 8 / 9 are the keypad keys ( ): the ST does not see the shift key)
         -- "as printed": a symbol needs Shift (pressed or not) or no Shift (hidden)
         -- MEGA + function key: Shift is pressed (MEGA + Shift + function key: the Shift keys as they are)
         if want_off then
            null;
         elsif (want_on and not fshift) or mfkey then
            if shift then
               map_key(m, key_pressed_n(m65_left_shift), st_lshift);
               map_key(m, key_pressed_n(m65_right_shift), st_rshift);
            else
               m(st_lshift) := '0';
            end if;
         elsif not fshift and not (keypad and (key_pressed_n(m65_8) = '0' or key_pressed_n(m65_9) = '0')) then
            map_key(m, key_pressed_n(m65_left_shift), st_lshift);
            map_key(m, key_pressed_n(m65_right_shift), st_rshift);
         end if;

         -- the symbol keys follow C_SETTLE after a change of the ST's Shift state
         st_shift   := m(st_lshift) = '0' or m(st_rshift) = '0';
         st_shift_d <= st_shift;
         if st_shift /= st_shift_d then
            settle_cnt <= C_SETTLE;
         elsif settle_cnt /= 0 then
            settle_cnt <= settle_cnt - 1;
         end if;
         if st_shift = st_shift_d and settle_cnt = 0 then
            m := m and sym;
         end if;
         map_key(m, key_pressed_n(m65_ctrl), st_ctrl);
         map_key(m, key_pressed_n(m65_alt), st_alt);
         if caps_counter /= 0 then
            m(st_caps) := '0';
         end if;

         -- cursor keys
         map_key(m, key_pressed_n(m65_up_crsr), st_up);
         map_key(m, key_pressed_n(m65_vert_crsr), st_down);
         map_key(m, key_pressed_n(m65_left_crsr), st_left);
         map_key(m, key_pressed_n(m65_horz_crsr), st_right);

         st_matrix_n_o <= m;
      end if;
   end process matrix;

end beh;


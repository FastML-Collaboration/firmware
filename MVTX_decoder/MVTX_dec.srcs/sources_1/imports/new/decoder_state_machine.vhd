--------------------------------------------------------------------------------
-- Title      : Continous Packet Sap Generator
-- Project    : CRU
-------------------------------------------------------------------------------
-- File       : cont_sap.vhd
-- Author     : Filippo Costa (filippo.costa@cern.ch), Tuan Mate Nguyen (tuan.mate.nguyen@cern.ch)
-------------------------------------------------------------------------------
-- Description: Generating standard (see RDH fields) formatted packets
--              emulating detector FEEs (see DDG/README.md)
-- 
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

Library xil_defaultlib;
use xil_defaultlib.ALL;

entity decoder_state_machine is
    generic (
    device : std_logic_vector(3 downto 0) := "1001"
    );
  port (
    --------------------------------------------------------------------------------
    -- CLK and RESET
    --------------------------------------------------------------------------------
    clk_i                     : in  std_logic;
    --clk_en_i                  : in  std_logic;
    rst_i                     : in  std_logic;
    
    pixel_coord_o              : out std_logic_vector(18 downto 0);
	pixel_ready_o              : out std_logic;

	------------------------------------------------------
	-- Data Control
	------------------------------------------------------
	data_i		              : in  std_logic_vector(79 downto 0);
	data_valid_i              : in std_logic
	--empty_fifo                : in  std_logic;
	--valid_fifo                : in  std_logic;
   -- d_o                       : out std_logic_vector(79 downto 0);
    --dv_o                      : out std_logic;
    --------------------------------------------------------------------------------
    -- MONITORING
    --------------------------------------------------------------------------------
   	--state_machine_mon_o : out std_logic_vector(10 downto 0);
    --sn                        : in  std_logic_vector( 7 downto 0)
    );
end decoder_state_machine;

architecture rtl of decoder_state_machine is
  -- CONSTANT
  constant c_RDH               : std_logic_vector(7 downto 0)  := x"00";
  constant c_IHW               : std_logic_vector(7 downto 0)  := x"e0";
  constant c_TDH               : std_logic_vector(7 downto 0)  := x"e8";
  constant c_TDT               : std_logic_vector(7 downto 0)  := x"f0";
  constant c_DDW               : std_logic_vector(7 downto 0)  := x"e4";
  constant c_CDW               : std_logic_vector(7 downto 0)  := x"f8";
  constant c_IDLE              : std_logic_vector(7 downto 0)  := x"ff";
  
  signal c_HEADER_SIZE         : std_logic_vector(7 downto 0)  := x"20";
  signal c_HEADER_VERSION      : std_logic_vector(7 downto 0)  := x"08";
  
  
  signal s_data             : std_logic_vector(79 downto 0);
  
  signal s_detector_field      : std_logic_vector(31 downto 0);
  signal s_source_id           : std_logic_vector(7 downto 0);
  signal s_feeid               : std_logic_vector(15 downto 0);
  signal s_rdh_bco             : std_logic_vector(39 downto 0);
  signal s_rdh_lhc             : std_logic_vector(11 downto 0);
  signal s_rdh_ttype           : std_logic_vector(31 downto 0);
  
  signal s_tdh_bco             : std_logic_vector(39 downto 0);
  signal s_tdh_lhc             : std_logic_vector(11 downto 0);
  
  signal s_tdh_last_bco        : std_logic_vector(39 downto 0) := (others => '0');
  signal s_tdh_last_lhc        : std_logic_vector(11 downto 0) := (others => '0');
  
  type t_chip_array is array (0 to 8) of std_logic_vector(71 downto 0);
  signal s_chip_data_fifo_in: t_chip_array;
  signal s_chip_data_fifo_out: t_chip_array;
  
  signal s_chip_data_valid      : std_logic_vector(8 downto 0);
  signal s_chip_data_fifo_wr      : std_logic_vector(8 downto 0);
  --signal s_chip_data_fifo_wr      : std_logic_vector(8 downto 0);
  signal s_chip_data_fifo_empty      : std_logic_vector(8 downto 0);
   
  
  
  constant c_PIPE_LENGTH       : natural := 5;
  constant c_SOP               : std_logic_vector(3 downto 0)  := x"1";
  constant c_EOP               : std_logic_vector(3 downto 0)  := x"2";
  constant c_MAX_EVENT_SIZE    : natural := 508;
  constant c_ZERO              : std_logic_vector(31 downto 0) := (others => '0');
    -- HEADER
 
  signal c_FEE_ID            : std_logic_vector(15 downto 0);
  -- header size = 4 words x 80 bits / (8 bit/byte) = 40 bytes
  
  signal c_PAR                 : std_logic_vector(15 downto 0) := x"0000";
  signal c_PRIORITY_BIT        : std_logic_vector(7 downto 0)  := x"00";
  constant c_SOURCE_ID         : std_logic_vector(7 downto 0)  := "00010001"; --> TRG is 17
  -- UNSIGNED
  signal u_ev_cnt              : unsigned(31 downto 0) := (others => '0');
  signal u_page_cnt            : unsigned(15 downto 0) := (others => '0');
-- INTEGER
  signal i_plcnt               : natural range 0 to 508;
  -- SIGNAL
  signal s_hbf_stop            : std_logic;
  signal s_hbttype             : std_logic_vector(31 downto 0);
  signal s_hborbit             : std_logic_vector(31 downto 0);
  signal s_hbbc                : std_logic_vector(11 downto 0);
  signal s_last_orbit          : std_logic_vector(31 downto 0);
  signal s_last_bc             : std_logic_vector(11 downto 0);
  signal s_ttype               : std_logic_vector(31 downto 0);
  signal s_last_ttype          : std_logic_vector(31 downto 0);
  signal HB                    : std_logic := '0';
  --signal run                   : std_logic := '1';
  signal wasHB, wasHBpacker       : std_logic := '0';
  signal s_payload_not_sent    : std_logic := '0';
  signal hbf_closed            : std_logic := '0';
  signal s_runpattern_rdh            :  std_logic_vector(31 downto 0);
  signal s_last_runpattern_rdh            :  std_logic_vector(31 downto 0);
  signal s_last_runpattern_rdh_ff            :  std_logic_vector(31 downto 0);
  signal hb_packer       : std_logic := '0';
  signal page_counter   : unsigned(15 downto 0) := (others => '0'); 
  
  signal last_rdh_sent : std_logic := '0';
   
  signal was_ctpreadout_start : std_logic := '0';
  signal was_ctpreadout_start_rst : std_logic := '0';
   signal was_ctpreadout_stop : std_logic := '0';
  signal was_ctpreadout_stop_rst : std_logic := '0';
  
  
   signal rd_en_s : std_logic_vector(8 downto 0) := (others => '0');
    signal fifo_rst_s : std_logic := '0';
    
    signal s_chip_data_empty      : std_logic_vector(8 downto 0);
    
    signal s_chip_fifo_1_active      : std_logic := '0';
    signal s_chip_fifo_2_active      : std_logic := '0';
    
    signal s_chip_fifo_event_error      : std_logic := '0';
    
    signal s_chip_fifo_switch      : std_logic := '0'; --0 1sts et, 1 second set
    
      type t_pixel_coord is array (0 to 8) of std_logic_vector(18 downto 0);
  signal s_pixel_coord: t_pixel_coord;
    
 --   signal s_pixel_coord              : std_logic_vector(18 downto 0):= (others => '0');
	signal s_pixel_ready              : std_logic_vector(8 downto 0) := (others => '0');
	
	signal s_pixel_read              : std_logic_vector(8 downto 0) := (others => '0');
	signal s_pixel_coord_out: t_pixel_coord;
	
    
     
  -- SM
  
  type t_states is (
    IDLE,
    RDH_WORD0,
    RDH_WORD1,
    RDH_WORD2,
    IHW,
    TDH,
    TDT,
    DDW,
    CDW,
    PAYLOAD,
    IB_DATA
    );
  signal s_ps           : t_states;
  signal s_cs           : t_states;
  signal s_ns           : t_states;
  
type chip_states is (
    IDLE,
    CHIP_HEADER,
    CHIP_TRAILER,
    CHIP_EMPTY_FRAME,
    REGION_HEADER,
    DATA_SHORT,
    DATA_LONG,
    BUSY_ON,
    BUSY_OFF
    );
  signal s_chip_cs           : chip_states;
  signal s_chip_ns           : chip_states;
  
  
--  component fifo_chipdata_72x64
--    PORT (
--    clk : IN STD_LOGIC;
--    srst : IN STD_LOGIC;
--    din : IN STD_LOGIC_VECTOR(71 DOWNTO 0);
--    wr_en : IN STD_LOGIC;
--    rd_en : IN STD_LOGIC;
--    dout : OUT STD_LOGIC_VECTOR(71 DOWNTO 0);
--    full : OUT STD_LOGIC;
--    empty : OUT STD_LOGIC;
--    valid : OUT STD_LOGIC;
--    wr_rst_busy : OUT STD_LOGIC;
--    rd_rst_busy : OUT STD_LOGIC
--  );
--  end component fifo_chipdata_72x64;

begin

fifo_rst_s <= rst_i;

 --c_FEE_ID <= "0000" & device & sn;

  

---- getting data payload from the fifos  
--  p_getdata : process(s_ns)
--  begin
--    case s_ns is
--      when SEND_DATA =>
--        data_rd_fifo <= '1';
--      when others =>
--        data_rd_fifo <= '0';
--    end case;
--   end process p_getdata;
   
  -- State machine
--  p_sm : process(clk_i)
--  begin
--    if rising_edge(clk_i) then
--      if rst_i = '1' then
--        s_cs <= IDLE;
--      --elsif clk_en_i = '1' then
--      else
--        s_cs <= s_ns;        
--      end if;
--    end if;
--  end process p_sm;
  
  
p_read_data : process(clk_i)
begin
    if rising_edge(clk_i) then
    s_chip_data_fifo_wr <= (others => '0');
    s_chip_data_fifo_in <= (others => (others => '0'));
        --s_ps <= s_cs;
        if data_valid_i = '1' then
            case data_i(79 downto 72) is
                when c_RDH =>
                    if data_i(15 downto 0) = c_HEADER_SIZE & c_HEADER_VERSION then
                        s_cs <= RDH_WORD0; 
                        s_detector_field <= data_i(71 downto 40);     
                        s_source_id      <= data_i(39 downto 32); 
                        s_feeid          <= data_i(31 downto 16);     
                    elsif s_cs = RDH_WORD0 then
                        s_cs <= RDH_WORD1;        
                        s_rdh_bco        <= data_i(71 downto 32);     
                        s_rdh_lhc        <= data_i(11 downto 0);            
                    elsif s_cs = RDH_WORD1 then
                        s_cs <= RDH_WORD2; 
                        s_rdh_ttype      <= data_i(31 downto 0);                  
                    end if;
      
                when c_IHW =>
                    s_cs <= IHW;
                
                when c_TDH =>
                    s_cs <= TDH;
                    s_tdh_bco        <= data_i(71 downto 32);     
                    s_tdh_lhc        <= data_i(27 downto 16); 
                    if ( data_i(71 downto 32) /= s_tdh_last_bco) and s_feeid(3 downto 0) = "0011" then
                        s_tdh_last_bco <=  data_i(71 downto 32);
                        
                     /*   if(s_chip_fifo_1_active = '0') then
                            s_chip_fifo_1_active <= '1';
                            s_chip_fifo_switch <= '0';
                        elsif(s_chip_fifo_2_active = '0') then
                            s_chip_fifo_2_active <= '1';
                            s_chip_fifo_switch <= '1';
                        else
                            s_chip_fifo_event_error <='1';
                        end if;*/
                  
                        
                        --terminate stream
                        s_chip_data_fifo_wr <= (others => '1');
                        s_chip_data_fifo_in <= (others => (others => '1'));                
                    end if;
                when c_TDT =>
                    s_cs <= TDT;
                
                when c_DDW =>
                    s_cs <= DDW;
                
                when c_CDW =>
                    s_cs <= CDW;
                
                when c_IDLE =>
                    s_cs <= IDLE;
                
                when others => --must be payload
                    --s_cs <= PAYLOAD;
                    --filtering curent file to have only one stave 
                    if s_feeid(3 downto 0) = "0011" then                    
                        if data_i(79 downto 77) = "001" then             
                            s_cs <= IB_DATA;
                           -- if (s_chip_fifo_event_error = '0' and  s_chip_fifo_switch = '0') then
                                case data_i(75 downto 72) is
                                    when x"0" =>
                                        s_chip_data_fifo_in(0) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(0) <= '1';
                                    when x"1" =>
                                        s_chip_data_fifo_in(1) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(1) <= '1';
                                    when x"2" =>
                                        s_chip_data_fifo_in(2) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(2) <= '1';
                                    when x"3" =>
                                        s_chip_data_fifo_in(3) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(3) <= '1';
                                    when x"4" =>
                                        s_chip_data_fifo_in(4) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(4) <= '1';
                                    when x"5" =>
                                        s_chip_data_fifo_in(5) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(5) <= '1';
                                    when x"6" =>
                                        s_chip_data_fifo_in(6) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(6) <= '1';
                                    when x"7" =>
                                        s_chip_data_fifo_in(7) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(7) <= '1';
                                    when x"8" =>
                                        s_chip_data_fifo_in(8) <= data_i(71 downto 0);
                                        s_chip_data_fifo_wr(8) <= '1';
                                    when others =>
                                        s_chip_data_fifo_wr <= (others => '0');        
                                end case;
                            --elsif(s_chip_fifo_event_error = '0' and  s_chip_fifo_switch = '1') then
                             
                           
                           -- end if;
                        end if;
                    end if;
            end case;
        end if;
    end if;
end process p_read_data;

gen_chips_fifo : for m in 0 to 8 generate
begin
chip_fifo: entity work.fifo_chipdata_72x64
    PORT MAP (
        CLK => clk_i,
        VALID => s_chip_data_valid(m),
        SRST => fifo_rst_s,
        wr_rst_busy => open,
        rd_rst_busy => open,
        WR_EN => s_chip_data_fifo_wr(m),
        RD_EN => rd_en_s(m),
        DIN => s_chip_data_fifo_in(m),--(m),
        DOUT => s_chip_data_fifo_out(m),
        FULL => open,
        EMPTY => s_chip_data_fifo_empty(m)    
      );
end generate;  

gen_alpide_decoder : for m in 0 to 8 generate
begin
alpide_dec: entity work.alpide_decoder
    PORT MAP (
        clk_i => clk_i,
        rst_i => '0',
        data_i => s_chip_data_fifo_out(m),
        pixel_coord_o  => s_pixel_coord(m),
	pixel_ready_o => s_pixel_ready(m),
	    fifo_valid_i => s_chip_data_valid(m),
	    fifo_empty_i => s_chip_data_fifo_empty(m),
	    fifo_read_o => rd_en_s(m)  
      );
end generate;  

gen_pixel_fifo_1 : for m in 0 to 8 generate
begin
pixel_fifo: entity work.fifo_hitdata_19x128
    PORT MAP (
        CLK => clk_i,
        VALID => open,
        SRST => fifo_rst_s,
        wr_rst_busy => open,
        rd_rst_busy => open,
        WR_EN => s_pixel_ready(m),
        RD_EN => s_pixel_read(m),
        DIN => s_pixel_coord(m),--(m),
        DOUT => s_pixel_coord_out(m),
        FULL => open,
        EMPTY => open    
      );
end generate; 

pixel_coord_o <=  s_pixel_coord(0);
pixel_ready_o <= s_pixel_ready(0);
s_pixel_read <= (others => '1');

--gen_shift : for m in 0 to 8 generate
--begin
----read : process(clk_i)
--begin
--    if rising_edge(clk_i) then
    
    
--    end if;
--    end process read;
--    end generate;




--  p_pcmb : process(s_cs)
--  begin
--    s_ns <= s_cs;
    
--    case s_cs is
--      --when IDLE =>
--      --  if (start_ir_data_taking_i = '1') then
--      --    s_ns <= SEND_SOP;
--      --  end if;
      
--      when RDH_WORD0 =>
--        s_ns <= RDH_WORD1;
             
--      when RDH_WORD1 =>
--        s_ns <= RDH_WORD2;        
      
--      when RDH_WORD2 =>
--        s_ns <= RDH_WORD3;        
                
--      when RDH_WORD3 =>
--        s_ns <= IHW;        
       
--      when SEND_RDH_WORD3 =>
--        if s_payload_not_sent = '1' and run_i = '1' then
--          s_ns <= SEND_DATA; 
--        elsif hbf_closed = '1' then
--          s_ns <= SEND_EOP;
--        else
--          s_ns <= WAIT_FOR_TRIGGER;
--        end if;
             
--      when WAIT_FOR_TRIGGER =>
--        if hbf_closed = '1' or hb_packer = '1' or run_i = '0' then
--          s_ns <= SEND_EOP;
--        elsif empty_fifo = '0' and run_i = '1' then
--          s_ns <= SEND_DATA;
--        end if;
    
--      when SEND_DATA =>
--        -- If reached 8 kB boundary, start new 8 kB page
--        if i_plcnt = c_MAX_EVENT_SIZE-1 then
--          s_ns <= SEND_EOP;          
--        else
--          if hbf_closed = '1' or hb_packer = '1' or run_i = '0' then
--            s_ns <= SEND_EOP;          
--          elsif empty_fifo = '0' and run_i = '1' then
--            s_ns <= SEND_DATA;
--          else
--            s_ns <= WAIT_FOR_TRIGGER;
--          end if;            
--        end if;
       
--      when SEND_EOP =>
--        if run_i = '0' and was_ctpreadout_stop = '0' then
--            s_ns <= IDLE;
--          else
--            s_ns <= NEW_RDH;
--          end if;      
--      when NEW_RDH =>
--          s_ns <= SEND_SOP;
              
--      when others =>
--        s_ns <= IDLE;
          
--    end case;
--  end process p_pcmb;


--  -------------------------------------------
--  -- Counter to make sure that one packet is
--  -- max 8KB (see state machine condition)
--  -------------------------------------------
--  p_payloadcnt : process(clk_i)
--  begin
--    if rising_edge(clk_i) then
--      if clk_en_i = '1' then
--        if s_cs = IDLE then
--          i_plcnt <= 0;        
--        elsif s_cs = SEND_DATA then
--          i_plcnt <= i_plcnt + 1;    
--        elsif s_cs = SEND_EOP then
--          i_plcnt <= 0; 
--        end if;
--      end if;
--    end if;
--  end process p_payloadcnt;

  
  ----------------------------------------------------------------------
  -- Process to count the number of sent events (1 for every trigger)
  ----------------------------------------------------------------------
--  p_ev_cnt : process(clk_i)
--  begin
--    if rising_edge(clk_i) then
--      if rst_i = '1' then
--        u_ev_cnt <= (others => '0');
--      elsif s_cs = SEND_DATA then
--        if clk_en_i = '1' then
--          u_ev_cnt <= u_ev_cnt + 1;
--        end if;
--      end if;
--    end if;
--  end process p_ev_cnt;


--  ------------------------------------------
--  -- Page counter, restarts for every HBF
--  ------------------------------------------
--  p_pagecnt : process(clk_i)
--  begin
--    if rising_edge(clk_i) then
--      if clk_en_i = '1' then
--        if s_cs = IDLE then
--          u_page_cnt <= (others => '0');
--        elsif s_cs = SEND_RDH_WORD3 then
--          -- Reset counter for every HBF
--          if hbf_closed = '1' then
--            u_page_cnt <= (others => '0');
--          else
--            u_page_cnt <= u_page_cnt + 1;
--        end if;      
--      end if;      
--    end if;
--    end if;
--  end process p_pagecnt;
  
--  ----------------------------------------------------------------------
--  -- Latching ttype, orbit and bc and run pattern based on HB signals
--  ----------------------------------------------------------------------
--  --last_rdh_sent
--  p_orbitbc : process(clk_i)
--  begin
--    if rising_edge(clk_i) then
--      s_runpattern_rdh <= runpattern_rdh_i;    
--      if last_rdh_sent = '1' and start_ir_data_taking_i = '0' then--SEND_RDH_WORD3
--        last_rdh_sent <= '0';
--        s_last_ttype <= s_hbttype;
--        s_last_orbit <= s_hborbit;
--        s_last_bc    <= s_hbbc;
--        s_last_runpattern_rdh <= s_runpattern_rdh;
--        if HB = '1'  then
--            s_hbttype <= trg_i;
--            s_hborbit <= orbitid;
--            s_hbbc    <= bcid;   
--        end if;
--      elsif ((s_cs = SEND_SOP and u_page_cnt /= 0) and start_ir_data_taking_i = '0') then  
--        s_last_bc    <= bcid when hbf_closed = '0' else x"DEB" ;
--        if HB = '1'  then
--            s_hbttype <= trg_i;
--            s_hborbit <= orbitid;
--            s_hbbc    <= bcid;   
--        end if;
--      elsif ((s_cs = SEND_RDH_WORD3 and u_page_cnt /= 0) and start_ir_data_taking_i = '0') then  
--        last_rdh_sent <= '1' when hbf_closed = '1';
--        if HB = '1'  then
--            s_hbttype <= trg_i;
--            s_hborbit <= orbitid;
--            s_hbbc    <= bcid;   
--        end if;
--      elsif HB = '1' and start_ir_data_taking_i = '0' then
--        s_hbttype <= trg_i;
--        s_hborbit <= orbitid;
--        s_hbbc    <= bcid;    
--      elsif ( start_ir_data_taking_i = '1' ) then
--        s_last_ttype <= trg_i;
--        s_last_orbit <= orbitid;
--        s_last_bc    <= bcid;
--        s_hbttype <= trg_i;
--        s_hborbit <= orbitid;
--        s_hbbc    <= bcid;
--        --s_runpattern_rdh <= runpattern_rdh_i;
--        s_last_runpattern_rdh <= runpattern_rdh_i;
--      end if;
--    end if;
--  end process p_orbitbc;
  
--  -- updating run pattern with SOP to avoid have it updated while sending stop bit of the previous frame
--  p_update_runptr : process(clk_i)
--  begin
--    if rising_edge(clk_i) then
--      if s_cs = SEND_SOP and start_ir_data_taking_i = '0' then
--        s_last_runpattern_rdh_ff <= s_last_runpattern_rdh;
--       end if;
--    end if;
--  end process p_update_runptr;
  
--  --------------------------------------------------------------------------------
--  -- Register the output of the SM
--  -- DATA conisists of the same 32 bit word repeated all over the GBT word
--  --------------------------------------------------------------------------------
--  p_out : process(clk_i)
--  begin
--    if rising_edge(clk_i) then
--      case s_cs is
--        when SEND_SOP =>
--          d_o(79 downto 76) <= c_SOP;
--          dv_o <= '0';
--          state_machine_mon_o(8 downto 0) <= "000000001";
          
--        when SEND_RDH_WORD0 =>
--          d_o  <= c_ZERO(31 downto 0) & c_SOURCE_ID & c_PRIORITY_BIT & c_FEE_ID & c_HEADER_SIZE & c_HEADER_VERSION;
--          dv_o <= '1';
--          state_machine_mon_o(8 downto 0) <= "000000010";

--        when SEND_RDH_WORD1 =>
--          d_o  <= c_ZERO(15 downto 0) & s_last_orbit & c_ZERO(19 downto 0) & s_last_bc;
--          dv_o <= '1';
--          state_machine_mon_o(8 downto 0) <= "000000100";
         
--        when SEND_RDH_WORD2 =>
--          d_o  <= c_ZERO(23 downto 0) & "0000000" & s_hbf_stop & std_logic_vector(u_page_cnt) & s_last_ttype; 
--          dv_o <= '1';
--          state_machine_mon_o(8 downto 0) <= "000001000";
       
--        when SEND_RDH_WORD3 =>
--          d_o  <= c_ZERO(31 downto 0) & c_PAR & s_last_runpattern_rdh_ff;
--          dv_o <= '1';
--          state_machine_mon_o(8 downto 0) <= "000010000";
        
--        when SEND_DATA =>
--            if( valid_fifo = '1'  and or_reduce(data_i(79 downto 0)) = '1' )then            
--              d_o <= data_i(79 downto 0);
--              dv_o <= '1';
--              state_machine_mon_o(8 downto 0) <= "000100000";
--            elsif( valid_fifo = '1'  and or_reduce(data_i(79 downto 0)) = '0' )then
--              d_o <= (others => '0'); 
--              dv_o <= '0';
--              state_machine_mon_o(8 downto 0) <= "001000000";
--            end if;
           
--        when SEND_EOP =>
--          d_o(79 downto 76) <= c_EOP;
--          d_o(75 downto 0) <= (others => '0');
--          dv_o <= '0';
--          state_machine_mon_o(8 downto 0) <= "010000000";
          
--        when others =>
--          d_o  <= (others => '0');
--          dv_o <= '0';
--          state_machine_mon_o(8 downto 0) <= "100000000";
--      end case;
--    end if;
--  end process p_out;

end rtl;
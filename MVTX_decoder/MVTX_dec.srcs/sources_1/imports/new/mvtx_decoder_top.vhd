----------------------------------------------------------------------------------
-- CTP readout - IR + TCR 
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;


entity ctpreadout is
    port (
    --------------------------------------------------------------------------------
    -- RESETs
    --------------------------------------------------------------------------------
    ipb_rst                    : in  std_logic;          --  General Reset
    rst_ctpreadout_i           : in std_logic_vector (4 downto 0);
	--------------------------------------------------------------------------------
    -- TIMING
    --------------------------------------------------------------------------------
    clk_bc_240                : in std_logic;
    tick_bc                   : in std_logic;
    tf_del2                   : in std_logic;
    hb_del4                   : in std_logic;
    --------------------------------------------------------------------------------
    -- GBT monitoring
    --------------------------------------------------------------------------------
    gbt_rx_clk240_en_i             : in std_logic_vector (1 to 2);
    gbt_rx_data_i                  : in std_logic_vector(83 downto 0); 
    gbt_rx_wordclk_i               : in std_logic_vector (1 to 2);   -- Comment. Tick, sync w.r.t GBT Clock Domain
    gbtRxReady_from_gbtExmplDsgn_i : in std_logic_vector (1 to 2); 
    rxIsData_from_gbtExmplDsgn_i   : in std_logic_vector (1 to 2); 
    gbt1_rx_data_o                 : out std_logic_vector(85 downto 0);
    gbt2_rx_data_o                 : out std_logic_vector(85 downto 0);
    gbt1_tx_data_o                 : out std_logic_vector (79 downto 0);
    gbt1_txIsDataSel_o             : out std_logic;
    gbt2_tx_data_o                 : out std_logic_vector (79 downto 0);
    gbt2_txIsDataSel_o             : out std_logic;
    --------------------------------------------------------------------------------
    -- Input Data		
    --------------------------------------------------------------------------------
    bcid                         : in  std_logic_vector (11 downto 0);
    orbitid                      : in  std_logic_vector (31 downto 0);
    d_i_ir                       : in  std_logic_vector (47 downto 0);    
    d_i_tcr                      : in  std_logic_vector (63 downto 0); 
    oredXOX                      : in  std_logic;
    --------------------------------------------------------------------------------
    -- Control
    --------------------------------------------------------------------------------
    ctpreadout_ctrl_i            : in std_logic_vector(7 downto 0);
    --------------------------------------------------------------------------------
    -- monitoring
    --------------------------------------------------------------------------------
    ctpreadout_stat_o         : out std_logic_vector(7 downto 0);
    --------------------------------------------------------------------------------
    -- State machine coders 
    --------------------------------------------------------------------------------
    ctpreadout_cnts_o  : out std_logic_vector (63 downto 0);
    --------------------------------------------------------------------------------
    -- Miscellaneous
    --------------------------------------------------------------------------------
    sn                        : in    std_logic_vector (7 downto 0)
        
        );
end ctpreadout;

architecture Behavioral of ctpreadout is

   signal start_ir_data_taking_aux, start_ir_data_taking_aux2 : std_logic := '0'; 
   signal start_tcr_data_taking_aux, start_tcr_data_taking_aux2 : std_logic := '0'; 
   signal stop_ir_data_taking_aux, stop_ir_data_taking_aux2 : std_logic := '0'; 
   signal stop_tcr_data_taking_aux, stop_tcr_data_taking_aux2  : std_logic := '0';
   signal start_ctpreadout          : std_logic := '0';
   signal stop_ctpreadout           : std_logic := '0';
   signal running_ctpreadout           : std_logic := '0';
   signal counter_SWT               : unsigned(31 downto 0) := (others => '0');
   signal ttype_for_ctpreadout      : std_logic_vector (31 downto 0);
       
   signal count       : std_logic_vector (67 downto 0) := (others => '0');
   signal orbit_reg   : std_logic_vector (31  downto 0) := (others => '0');
   signal pattern_reg : std_logic_vector (31  downto 0) := (others => '0');
   signal tcr_data    : std_logic_vector (67  downto 0) := (others => '0');
   signal ir_data     : std_logic_vector (67  downto 0) := (others => '0');

   -- CDC GBT to OLT
   signal dc_fifo1_gbt2olt_din, gbt1_rx_data : std_logic_vector(85 downto 0);
   signal dc_fifo1_gbt2olt_rd_en, dc_fifo1_gbt2olt_empty : std_logic;
   signal dc_fifo2_gbt2olt_din, gbt2_rx_data : std_logic_vector(85 downto 0);
   signal dc_fifo2_gbt2olt_rd_en, dc_fifo2_gbt2olt_empty : std_logic;
  -- signal rxIsData_from_gbtExmplDsgn_s                   : std_logic_vector (1 to 2) := (others => '0'); 

  --signal tickpipe         : std_logic_vector(6 downto 1);
  signal tcr_data_del1    : std_logic_vector (67  downto 0) := (others => '0');
   signal ir_data_del1     : std_logic_vector (67  downto 0) := (others => '0');
   
   signal tcr_data_del2    : std_logic_vector (67  downto 0) := (others => '0');
   signal ir_data_del2     : std_logic_vector (67  downto 0) := (others => '0');
   signal tcr_data_del3    : std_logic_vector (67  downto 0) := (others => '0');
   signal ir_data_del3     : std_logic_vector (67  downto 0) := (others => '0');
   signal tcr_data_del4    : std_logic_vector (67  downto 0) := (others => '0');
   signal ir_data_del4     : std_logic_vector (67  downto 0) := (others => '0');
   
   signal tcr_data_sel    : std_logic_vector (67  downto 0) := (others => '0');
   signal ir_data_sel     : std_logic_vector (67  downto 0) := (others => '0');
   
   signal ir_counters     : std_logic_vector (17  downto 0) := (others => '0');
   signal tcr_counters     : std_logic_vector (17  downto 0) := (others => '0');
   
   signal rst_cdc_s  : std_logic;
   signal rst_prsg_s  : std_logic;
   signal rst_packer_s  : std_logic;
   signal rst_fifo_s : std_logic;
   signal rst_state_machine_s : std_logic;
   
   signal ctrl                      :  std_logic_vector(31 downto 0);
   signal threshold_ir                 :  std_logic_vector(31 downto 0);
   signal threshold_tcr                :  std_logic_vector(31 downto 0);
   signal run_pattern_rdh              :  std_logic_vector(31 downto 0);
   signal ir_mask_low                  :  std_logic_vector(31 downto 0);
   signal ir_mask_high                 :  std_logic_vector(31 downto 0);
   
   signal swt_monitoring            :  std_logic_vector(31 downto 0);
   signal orbit_xox                 :  std_logic_vector (31 downto 0);
   signal statusbits_s                :  std_logic_vector (31 downto 0);
   signal errorbits_s                 :  std_logic_vector (31 downto 0);
   
   signal cdc_gbt1_error  : std_logic;
   signal cdc_gbt2_error  : std_logic;
   
   signal cdc_gbt1_error_sticky  : std_logic;
   signal cdc_gbt2_error_sticky  : std_logic;
   signal rst_sticky  : std_logic;
  
begin
--========================
-- generate resets
--========================

rst_sync : process (clk_bc_240) begin 
      if (rising_edge(clk_bc_240)) then
        rst_cdc_s  <= ipb_rst or rst_ctpreadout_i(0);
        rst_prsg_s  <= ipb_rst or rst_ctpreadout_i(1);
        rst_packer_s   <= ipb_rst or rst_ctpreadout_i(2);
        rst_fifo_s  <= ipb_rst or rst_ctpreadout_i(3);
        rst_state_machine_s  <= ipb_rst or rst_ctpreadout_i(4);
        rst_sticky <= ipb_rst or ctrl(16);
     end if;
 end process rst_sync;
 
 

--========================
-- GBT for IR
--========================

dc_fifo1_gbt2olt_din(85) <= gbt_rx_clk240_en_i(1);
dc_fifo1_gbt2olt_din(84) <= rxIsData_from_gbtExmplDsgn_i(1);
dc_fifo1_gbt2olt_din(83 downto 0) <= gbt_rx_data_i(83 downto 0);
 
    

--========================
-- GBT for TCR
--========================

dc_fifo2_gbt2olt_din(85) <= gbt_rx_clk240_en_i(2);
dc_fifo2_gbt2olt_din(84) <= rxIsData_from_gbtExmplDsgn_i(2);
dc_fifo2_gbt2olt_din(83 downto 0) <= gbt_rx_data_i(83 downto 0);


--==============================
-- START/STOP
--==============================
process (clk_bc_240) begin 
          if (rising_edge(clk_bc_240)) then -- 240 MHz !!!
             if (gbt1_rx_data(85) = '1') then                      
                if (gbt1_rx_data(84) = '0' and gbt1_rx_data(79 downto 0) = x"300000000000DEADBEEF") then -- SWT word is when GBT bits 79:76 = 0x3
                   start_ir_data_taking_aux <= '1';
                elsif (gbt1_rx_data(84) = '0' and gbt1_rx_data(79 downto 0) = x"300000000000BEEFDEAD") then -- SWT word is when GBT bits 79:76 = 0x3
                   stop_ir_data_taking_aux <= '1';
                elsif (tf_del2 = '1') then
                   start_ir_data_taking_aux <= '0';
                   stop_ir_data_taking_aux <= '0';
                end if;
             end if;
         end if;
end process;

process (clk_bc_240) begin 
          if (rising_edge(clk_bc_240)) then -- 240 MHz !!!
             if (gbt2_rx_data(85) = '1') then                        
                if (gbt2_rx_data(84) = '0' and gbt2_rx_data(79 downto 0) = x"300000000000DEADBEEF") then -- SWT word is when GBT bits 79:76 = 0x3
                   start_tcr_data_taking_aux <= '1';
                elsif (gbt2_rx_data(84) = '0' and gbt2_rx_data(79 downto 0) = x"300000000000BEEFDEAD") then -- SWT word is when GBT bits 79:76 = 0x3
                   stop_tcr_data_taking_aux <= '1';
                elsif (tf_del2 = '1') then
                   start_tcr_data_taking_aux <= '0';
                   stop_tcr_data_taking_aux <= '0';
                end if;
             end if;
         end if;
end process;
         
process (clk_bc_240) begin 
      if (rising_edge(clk_bc_240)) then -- 240 MHz !!!
         if (tick_bc = '1') then      
            start_ir_data_taking_aux2 <= start_ir_data_taking_aux;
            stop_ir_data_taking_aux2  <= stop_ir_data_taking_aux;
            start_tcr_data_taking_aux2 <= start_tcr_data_taking_aux;
            stop_tcr_data_taking_aux2  <= stop_tcr_data_taking_aux;        
         end if;
      end if;        
end process;

start_ctpreadout <= (start_ir_data_taking_aux2 or start_tcr_data_taking_aux2) and tf_del2;
stop_ctpreadout  <= (stop_ir_data_taking_aux2 or stop_tcr_data_taking_aux2) and tf_del2;

process (clk_bc_240) begin 
      if (rising_edge(clk_bc_240)) then -- 240 MHz !!!
         if (tick_bc = '1') then            
            running_ctpreadout <= (running_ctpreadout or start_ctpreadout) and not stop_ctpreadout;
         end if;
      end if;        
end process;

statusbits_s(0) <= running_ctpreadout;

-- ===========
-- Counter SWT
-- ===========
process(clk_bc_240)
  begin
    if rising_edge(clk_bc_240) then
      if (tick_bc = '1') then
        if (start_ctpreadout = '1' or stop_ctpreadout = '1')  then
          counter_SWT <= counter_SWT + 1;
        end if;
      end if;
    end if;
  end process;

swt_monitoring <= std_logic_vector(counter_SWT);
    
--==============================
-- Change Run Pattern RDH
--==============================
change_run_pattern: process(clk_bc_240)
    begin
        if (rising_edge(clk_bc_240)) then
          if (oredXOX = '1') then
             pattern_reg   <= run_pattern_rdh;
             orbit_xox     <= orbitid;
          end if;                 
        end if;
    end process change_run_pattern;
    

--==============================
-- Counter Mode
--==============================
process (clk_bc_240)
    begin
        if (rising_edge(clk_bc_240)) then
            if (tick_bc = '1') then
                count <= std_logic_vector(unsigned(count) + '1');   -- counting up
                if count(11 downto 0) = "111111111111" then
                  count <= (others => '0');
                end if;
            end if;
        end if;
    end process;

--==============================
-- Trigger type
--==============================
ttype_for_ctpreadout <= "00000000000000000000" & tf_del2 & "000000000" & hb_del4 & '0';

--==============================
-- IR mask
--==============================
process (clk_bc_240)
    begin
        if (rising_edge(clk_bc_240)) then
            ir_data (47 downto 0) <= (d_i_ir and (ir_mask_high(23 downto 0) & ir_mask_low(23 downto 0)));
            ir_data(67 downto 48) <= (others => '0');
        end if;
    end process;
    
--==============================
-- IR and TCR programable delay pipeline
--==============================
    
--tickpipe <= tickpipe(5 downto 1) & tick_bc when rising_edge(clk_bc_240);

process (clk_bc_240) begin
        if (rising_edge(clk_bc_240)) then
            if (tick_bc = '1') then
                ir_data_del1 <= ir_data;
                ir_data_del2 <= ir_data_del1;
                ir_data_del3 <= ir_data_del2;
                ir_data_del4 <= ir_data_del3;
                
                tcr_data_del1 <= tcr_data;
                tcr_data_del2 <= tcr_data_del1;
                tcr_data_del3 <= tcr_data_del2;
                tcr_data_del4 <= tcr_data_del3;
            end if;
        end if;
    end process;
    
with ctrl(11 downto 8) select 
    ir_data_sel <= ir_data_del1 when "0001",
	               ir_data_del2 when "0010",
	               ir_data_del3 when "0100",
	               ir_data_del4 when "1000",
	               ir_data when others;

with ctrl(15 downto 12) select 
    tcr_data_sel <= tcr_data_del1 when "0001",
	                tcr_data_del2 when "0010",
	                tcr_data_del3 when "0100",
	                tcr_data_del4 when "1000",
	                tcr_data when others;





end Behavioral;

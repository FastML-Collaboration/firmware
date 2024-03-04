----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/20/2023 06:13:27 PM
-- Design Name: 
-- Module Name: alpide_decoder - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_unsigned.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity alpide_decoder is
    port (
    clk_i                     : in  std_logic;
    rst_i                     : in  std_logic;
	------------------------------------------------------
	-- Data Control
	------------------------------------------------------
	data_i		              : in  std_logic_vector(71 downto 0);
	pixel_coord_o              : out std_logic_vector(18 downto 0);
	pixel_ready_o              : out std_logic;
	
	fifo_valid_i              : in std_logic;
	
	fifo_empty_i              : in std_logic;
	
	fifo_read_o              : out std_logic
	);
end alpide_decoder;

architecture Behavioral of alpide_decoder is


    constant c_IDLE_1                : std_logic_vector(3 downto 0)  := x"f";
    constant c_IDLE_2                : std_logic_vector(3 downto 0)  := x"0";
    constant c_HEADER                : std_logic_vector(3 downto 0)  := x"a";
    constant c_TRAILER               : std_logic_vector(3 downto 0)  := x"b";
    constant c_EMPTY                 : std_logic_vector(3 downto 0)  := x"e";
    constant c_REGION                : std_logic_vector(2 downto 0)  := "110";
    constant c_DATA_SHORT            : std_logic_vector(1 downto 0)  := "01";
    constant c_DATA_LONG             : std_logic_vector(1 downto 0)  := "00";

    signal data_shift                : std_logic_vector(71 downto 0);
    signal data_shift_next           : std_logic_vector(71 downto 0);
    signal s_region_id               : std_logic_vector(4 downto 0);
    signal s_encoder_id              : std_logic_vector(3 downto 0);
    signal s_addr                    : std_logic_vector(9 downto 0);
    signal s_hitmap                  : std_logic_vector(6 downto 0);
    signal s_bytes                   : UNSIGNED(4 downto 0);
    
    signal bytes_on_stack            : integer := 0;
    signal s_data                    : std_logic_vector(71 downto 0);
    
    signal s_header_continue         : std_logic := '0';
    signal s_data_short_continue     : std_logic := '0';
    signal s_data_long_1_continue    : std_logic := '0';
    signal s_data_long_2_continue    : std_logic := '0';
    
    signal s_fifo_read_request       : std_logic := '0'; 
    signal s_fifo_read_wait_ff1      : std_logic := '0';
    signal s_fifo_read_wait_ff2      : std_logic := '0';
    signal s_fifo_read_wait_ff3      : std_logic := '0';
    
    signal s_data_short_decode       : std_logic := '0';
    signal s_data_long_decode        : std_logic := '0';
    signal s_pixel_ready             : std_logic := '0';
    
    signal s_data_long_decoding      : std_logic := '0';
    signal s_data_long_decoding_done : std_logic := '0';
    
    signal s_col                     : std_logic_vector(9 downto 0);
    signal s_row                     : std_logic_vector(8 downto 0);
    
    signal s_hitmap_shift            : std_logic_vector(6 downto 0);
    signal s_addr_shift              : std_logic_vector(9 downto 0);
    
    signal s_arbiter                 : std_logic := '0';
    signal s_data_valid              : std_logic := '0';
    signal s_idle                    : std_logic := '0';


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

begin

-- to prohibit another read signal before data are valid
p_read_busy : process(clk_i) begin
    if rising_edge(clk_i) then            
        s_fifo_read_wait_ff2 <= s_fifo_read_wait_ff1;
        s_fifo_read_wait_ff3 <= s_fifo_read_wait_ff2;
    end if;
end process p_read_busy;   

-- iterate through bytes in GBT word
p_decode : process(clk_i) begin
    if rising_edge(clk_i) then
        s_data_short_decode <= '0';
        s_data_long_decode <= '0';
        s_data_valid <= '0';
        s_idle <= '0';

        -- read data from chip buffer
        if ((s_fifo_read_request = '1' or bytes_on_stack = 0) and fifo_empty_i = '0' and s_fifo_read_wait_ff1 = '0' and s_fifo_read_wait_ff2 = '0' and s_fifo_read_wait_ff3 = '0') then
            fifo_read_o <= '1';
            s_fifo_read_wait_ff1 <= '1';         
            s_fifo_read_request <= '0';   
        else
            fifo_read_o <= '0';    
            s_fifo_read_wait_ff1 <= '0';  
        end if;
    
        -- valid fifo data, push to memory
        if fifo_valid_i = '1' then
            s_data <= data_i(71 downto 0);
            s_data_valid <= '1';
            -- memory empty or idle, push directly to shift register (saves one cycle)
            if (bytes_on_stack = 0 or bytes_on_stack = 9 ) then
                data_shift <= data_i(71 downto 0);
            end if;
            -- update data in memory
            bytes_on_stack <= 9;          
        end if;
    
        -- process only if allowed to proccess (no long word decoding or waiting for new data)
        if s_arbiter = '1' then
            -- chip header
            if (data_shift(7 downto 4) = c_HEADER ) then
                s_chip_cs <= CHIP_HEADER;          
                if (bytes_on_stack >= 2) then
                    data_shift <=x"FFFF" & data_shift(71 downto 16);
                    bytes_on_stack <= bytes_on_stack - 2;
                -- possible chopped header, should not happen
                elsif (s_header_continue = '1') then
                    s_header_continue <= '0';  
                    data_shift <=x"FF" & s_data(71 downto 8);
                    bytes_on_stack <= bytes_on_stack - 1;
                else 
                    s_header_continue <= '1';    
                    s_fifo_read_request <= '1';         
                end if;        
                --trailer
                elsif (data_shift(7 downto 4) = c_TRAILER ) then
                    s_chip_cs <= CHIP_TRAILER;   
                    if (bytes_on_stack >= 1) then
                        data_shift <=x"FF" & data_shift(71 downto 8);  
                        bytes_on_stack <= bytes_on_stack - 1;
                    end if;
                --empty frame
                elsif (data_shift(7 downto 4) = c_EMPTY) then
                    s_chip_cs <= CHIP_EMPTY_FRAME;
                    if (bytes_on_stack >= 2) then
                        data_shift <=x"FFFF" & data_shift(71 downto 16);     
                    end if;
                --region header
                elsif (data_shift(7 downto 5) = c_REGION ) then
                    s_chip_cs <= REGION_HEADER;                   
                    if (bytes_on_stack >= 1) then
                        data_shift <=x"FF" & data_shift(71 downto 8);  
                        s_region_id <= data_shift(4 downto 0);
                        bytes_on_stack <= bytes_on_stack - 1;
                    end if;
                --data short
                elsif (data_shift(7 downto 6) = c_DATA_SHORT) then
                    s_chip_cs <= DATA_SHORT;
                    --full data short (2b) in memory
                    if (bytes_on_stack >= 2 and s_data_short_continue = '0') then
                        data_shift <=x"FFFF" & data_shift(71 downto 16);
                        s_encoder_id <= data_shift(5 downto 2);
                        s_addr <= data_shift(1 downto 0) & data_shift(15 downto 8);
                        bytes_on_stack <= bytes_on_stack - 2;
                        s_data_short_decode <= '1';
                    --1 byte in previous word, 1 in current word
                    elsif (s_data_short_continue = '1') then
                        s_data_short_continue <= '0';  
                        data_shift <=x"FF" & s_data(71 downto 8);
                        s_encoder_id <= data_shift(5 downto 2);
                        s_addr <= data_shift(1 downto 0) & s_data(7 downto 0);
                        bytes_on_stack <= bytes_on_stack - 1;
                        s_data_short_decode <='1';
                    --only 1 byte in current word, initiate read
                    else 
                        s_data_short_continue <= '1'; 
                        s_fifo_read_request <= '1';
                        s_data_short_decode <= '0';            
                    end if;
                --long data word
                elsif (data_shift(7 downto 6) =  c_DATA_LONG ) then
                    s_chip_cs <= DATA_LONG; 
                    --full data long (3b) in memory
                    if (bytes_on_stack >= 3 and s_data_long_1_continue = '0' and s_data_long_2_continue = '0') then
                        data_shift <=x"FFFFFF" & data_shift(71 downto 24); 
                        bytes_on_stack <= bytes_on_stack - 3;
                        s_encoder_id <= data_shift(5 downto 2);
                        s_addr <= data_shift(1 downto 0) & data_shift(15 downto 8);
                        s_hitmap <= data_shift(22 downto 16);
                        s_data_long_decode <= '1';
                    --1b in previous word, 2b in current
                    elsif (s_data_long_1_continue = '1') then
                        s_data_long_1_continue <= '0';  
                        data_shift <=x"FFFF" & s_data(71 downto 16);
                        s_encoder_id <= data_shift(5 downto 2);
                        s_addr <= data_shift(1 downto 0) & s_data(7 downto 0);
                        s_hitmap <= s_data(14 downto 8);
                        bytes_on_stack <= bytes_on_stack - 2;
                        s_data_long_decode <='1';
                    --2b in previous word, 1b in current
                    elsif (s_data_long_2_continue = '1') then
                        s_data_long_2_continue <= '0';  
                        data_shift <=x"FF" & s_data(71 downto 8);
                        s_encoder_id <= data_shift(5 downto 2);
                        s_addr <= data_shift(1 downto 0) & data_shift(15 downto 8);
                        s_hitmap <= s_data(6 downto 0);
                        bytes_on_stack <= bytes_on_stack - 1;
                        s_data_long_decode <='1';
                    --only 2b in current word, init read
                    elsif (bytes_on_stack >= 2) then
                        s_data_long_2_continue <= '1';   
                        s_fifo_read_request <= '1';
                        s_data_long_decode <= '0';
                    --only 1b in current word, init read
                    else 
                        s_data_long_1_continue <= '1';   
                        s_fifo_read_request <= '1';   
                        s_data_long_decode <= '0';       
                    end if; 
                -- IDLE, either 0xFF ot 0x00
                elsif (data_shift(7 downto 4) =  c_IDLE_1 or data_shift(7 downto 4) =  c_IDLE_2 ) then
                    s_chip_cs <= IDLE;
                    s_idle <= '1'; -- terminate arbiter
                    bytes_on_stack <= 0;              
                else
                    null;           
                end if; 
        end if;
    end if;
end process p_decode;

--active decoding of long word
s_data_long_decoding <= (s_data_long_decoding or s_data_long_decode) and not s_data_long_decoding_done;
--arbiter for GBT word read
--activated with FIFO valid data ot finishing long decoding, inhibited by fifo read requist, long data decoding or idle
s_arbiter <= (s_arbiter or s_data_valid or s_data_long_decoding_done) and not (s_fifo_read_request or s_data_long_decode or s_idle);

-- hit decoder
p_write_hit : process(clk_i) begin
    if rising_edge(clk_i) then   
        s_data_long_decoding_done <= '0';
        s_pixel_ready <= '0';
        -- short word
        if s_data_short_decode = '1' then
            s_col <= ((s_region_id & s_encoder_id & '0') OR ((s_addr XOR ('0' & s_addr(9 downto 1))) AND "0000000001"));
            s_row <= s_addr(9 downto 1); -- addr/2
            s_pixel_ready <= '1';
        end if;
        --long word
        if s_data_long_decode = '1' and s_data_long_decoding = '1' then
            s_hitmap_shift <= s_hitmap;
            s_addr_shift <= s_addr;
        elsif s_data_long_decode = '0' and s_data_long_decoding = '1' then    
            s_hitmap_shift <= '0' & s_hitmap_shift(6 downto 1);  
            if or_reduce(s_hitmap_shift) = '1' then
                s_addr_shift <= s_addr_shift + x"1";
                if s_hitmap_shift(0) = '1' then
                    s_col <= ((s_region_id & s_encoder_id & '0') OR ((s_addr_shift XOR ('0' & s_addr_shift(9 downto 1))) AND "0000000001"));
                    s_row <= s_addr_shift(9 downto 1); -- addr/2
                    s_pixel_ready <= '1';
                end if;     
            end if;
            -- rest hitmap empty, terminate decoding   
            if or_reduce(s_hitmap_shift) = '0' then
                s_data_long_decoding_done <= '1';
            end if;  
        end if;
    end if;
end process p_write_hit;   

pixel_coord_o <=  s_col & s_row;
pixel_ready_o <= s_pixel_ready;
    
    
end Behavioral;

function lengths = huffman_tables(name)
% HUFFMAN_TABLES Huffman code lengths for S4 = 0..15 (1x16).
%
%   huffman_tables('kiem')            Kiem's Appendix A table (Table A.1),
%                                     used for both DRHE and LPC originally.
%   huffman_tables('drhe_retrained')  re-derived for DRHE on ColoRadar
%   huffman_tables('lpc_retrained')   re-derived for LPC on ColoRadar
%
%   The re-derived tables are the ones in the FPGA cores
%   (DRHE_TDM_HUFFMAN_TABLE / LPC_TDM_HUFFMAN_TABLE in hls_component):
%   trained on ColoRadar frames 0-4 with a +1 pseudo-count
%   (verify_indep/retrain_complete.json, "drhe12" and "lpc1224").
%   To retrain from other frames instead, use huffman_code_lengths().
    switch lower(name)
        case 'kiem'
            lengths = [4, 3, 2, 2, 2, 5, 6, 7, 8, 9, 10, 11, 14, 14, 13, 12];
        case 'drhe_retrained'
            lengths = [3, 2, 1, 4, 5, 6, 7, 8, 9, 10, 11, 14, 14, 13, 13, 13];
        case 'lpc_retrained'
            lengths = [3, 1, 2, 4, 5, 6, 7, 8, 9, 10, 13, 13, 13, 13, 12, 12];
        otherwise
            error('huffman_tables: unknown table "%s"', name);
    end
end

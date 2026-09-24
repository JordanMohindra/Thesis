cd('C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\Thesis\ThesisA\Matlab_Sim');
diary('C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\Thesis\ThesisA\_verify\lfr_rerun.log'); diary on;
out = compare_quantisation_lfr(0,false); disp(out.FX16uniform); disp(out.FX16linear); disp(out.FX16lfr); diary off;

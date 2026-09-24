cd('C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\Thesis\ThesisA\Matlab_Sim');
setenv('DRHE_MAX_FRAMES','50'); diary('C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\Thesis\ThesisA\_verify\phase1_rerun.log'); diary on;
t0=tic; main_simulation_coloradar_batch; fprintf('ELAPSED %.1f s\n',toc(t0)); diary off;

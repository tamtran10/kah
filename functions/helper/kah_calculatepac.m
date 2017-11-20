function kah_calculatepac(subject, chanA, chanB, pairnum, clusterpath)
% Load theta phase data for only channels of interest. 
theta = matfile([clusterpath 'thetaphase/' subject '_FR1_thetaphase.mat']);
times = theta.times;
thetaphase = theta.data([chanA, chanB], :, :);

% Load HFA amplitude data for only channels of interest.
hfa = matfile([clusterpath 'hfaamp/' subject '_FR1_hfaamp.mat']);
hfaamp = hfa.data([chanA, chanB], :, :);
hfaamp = flip(hfaamp, 1); % so that theta and HFA from opposite channels are matched up
[ndirection, ~, ntrial] = size(hfaamp);

% Limit to post-stimulus period.
timewin = dsearchn(times(:), [0; 1600]);
thetaphase = thetaphase(:, timewin(1):timewin(2), :);
hfaamp = hfaamp(:, timewin(1):timewin(2), :);

% Load samples to shift by. 
shifttrials = matfile([clusterpath 'shifttrials/' subject '_FR1_trialshifts_default_pac_between_ts.mat']);
shifts = squeeze(shifttrials.shifttrials(pairnum, :, :, :));
nsurrogate = size(shifts, 3);

% Calculate tsPAC in both directions for each trial, + surrogate PAC.
pacbetween = nan(ntrial, ndirection, nsurrogate + 1);
for itrial = 1:ntrial
    for idirection = 1:ndirection
        phasechan = thetaphase(idirection, :, itrial);
        ampchan = hfaamp(idirection, :, itrial);
        
        [pacbetween(itrial, idirection, nsurrogate + 1), pacbetween(itrial, idirection, 1:nsurrogate)] = ...
            calculatepac(phasechan, ampchan, 'ozkurt', squeeze(shifts(itrial, idirection, :)));
    end
end

% Save pacbetween values as new variable in output file, variable name including the pair number.
% PAC from each pair of electrodes will in this way have a unique variable name.
pairvarname = ['pair' num2str(pairnum)];
eval([pairvarname ' = pacbetween;']);

outputfile = [clusterpath 'tspac/' subject '_FR1_pac_between_ts_0_1600_resamp.mat'];
save(outputfile, '-append', pairvarname);
end

% output = matfile(outputfile, 'Writable', true);
% output.(['pair' num2str(pairnum)]) = pacbetween;
% Load information about subjects in Project Kahana. 
% Includes path, demographic, and channel, and artifact info. 
% Surface channels are prioritized. So, depth channels may or may not be
% noted as broken or epileptic. 

function info = kah_info
warning off

info = struct;

% Set path to Kahana folder on shared VoytekLab server.
info.path.kah = '/Volumes/voyteklab/common/data2/kahana_ecog_RAMphase1/';

% Set path to .csv file with demographic information.
info.path.demfile = [info.path.kah 'Release_Metadata_20160930/RAM_subject_demographics.csv'];

% Set current release of Kahana data.
info.release = 'r1';

% Set path to experiment data.
info.path.exp = [info.path.kah 'session_data/experiment_data/protocols/' info.release '/subjects/'];

% Set path to anatomical data.
info.path.surf = [info.path.kah 'session_data/surfaces/'];

% Get all subject identifiers.
info.subj = dir(info.path.exp);
info.subj = {info.subj.name};
info.subj(contains(info.subj, '.')) = [];

% Get info from demographic file.
demfile = fopen(info.path.demfile);
deminfo = textscan(demfile, '%s %s %f %s %s %s %s %s %s %s %s %s', 'delimiter', ',', 'headerlines', 1);
fclose(demfile);

% OPTIONAL:

% % Subjects with >= age 18, sampling rate >= 999 Hz, temporal & frontal grids, FR1 task, > 20 correct trials, and relatively clean data
% info.subj = {'R1032D', 'R1128E', 'R1034D', 'R1167M', 'R1142N', 'R1059J', 'R1020J', 'R1045E'};

% Subjects with age >= 18, fs >= 999, FR1, at least 3 T/F
info.subj = {'R1020J' 'R1032D' 'R1033D' 'R1034D' 'R1045E' 'R1059J' 'R1075J' 'R1080E' 'R1120E' 'R1128E' 'R1135E' ...
    'R1142N' 'R1147P' 'R1149N' 'R1151E' 'R1154D' 'R1162N' 'R1166D' 'R1167M' 'R1175N'};

% Get gender, ages, and handedness of all subjects.
[info.gender, info.hand] = deal(cell(size(info.subj)));
info.age = nan(size(info.subj));

for isubj = 1:numel(info.subj)
    info.gender(isubj) = deminfo{2}(strcmpi(info.subj{isubj}, deminfo{1}));
    info.age(isubj) = deminfo{3}(strcmpi(info.subj{isubj}, deminfo{1}));
    info.hand(isubj) = deminfo{12}(strcmpi(info.subj{isubj}, deminfo{1}));
end

% Load anatomical atlases.
talatlas = ft_read_atlas('TTatlas+tlrc.HEAD');
mniatlas = ft_read_atlas('ROI_MNI_V4.nii');

% For each subject, extract anatomical, channel, and electrophysiological info.
for isubj = 1:numel(info.subj)
    
    % Get current subject identifier.
    subjcurr = info.subj{isubj};
    disp([num2str(isubj) ' ' subjcurr])

    % Get path for left- and right-hemisphere pial surf files.
    info.(subjcurr).lsurffile = [info.path.surf subjcurr '/surf/lh.pial'];
    info.(subjcurr).rsurffile = [info.path.surf subjcurr '/surf/rh.pial'];
    
    % Get experiment-data path for current subject.
    subjpathcurr = [info.path.exp subjcurr '/'];
        
    % Get subject age.
    info.(subjcurr).age = info.age(isubj);
    
    % Get path for contacts.json and get all contact information.
    info.(subjcurr).contactsfile = [subjpathcurr 'localizations/0/montages/0/neuroradiology/current_processed/contacts.json'];
    contacts = loadjson(info.(subjcurr).contactsfile);
    contacts = contacts.(subjcurr).contacts;
    
    % Get labels for all channels.
    info.(subjcurr).allchan.label = fieldnames(contacts);
    
    % For each channel...
    for ichan = 1:length(info.(subjcurr).allchan.label)
        chancurr = contacts.(info.(subjcurr).allchan.label{ichan});
        
        % ...get channel type (grid, strip, depth)...
        info.(subjcurr).allchan.type{ichan} = chancurr.type;
        
        % and region labels and xyz coordinates per atlas.
        atlases = {'avg', 'avg_0x2E_dural', 'ind', 'ind_0x2E_dural', 'mni', 'tal', 'vox'};
        for iatlas = 1:length(atlases)
             % Get current atlas info for the channel.
            try
                atlascurr = chancurr.atlases.(atlases{iatlas});
            catch
                continue % if atlas not included for this subject.
            end
            
            % Extract region label for channel.
            if isempty(atlascurr.region)
                atlascurr.region = 'NA'; % if no region label is given in this atlas. For MNI and TAL, this will be filled in later.
            end
            info.(subjcurr).allchan.(atlases{iatlas}).region{ichan} = atlascurr.region;
            
            % Convert xyz coordinates to double, if necessary (due to NaNs in coordinates).
            coords = {'x', 'y', 'z'};
            for icoord = 1:length(coords)
                if ischar(atlascurr.(coords{icoord}))
                    atlascurr.(coords{icoord}) = str2double(atlascurr.(coords{icoord}));
                end
            end
            
            % Extract xyz coordinates.
            info.(subjcurr).allchan.(atlases{iatlas}).xyz(ichan,:) = [atlascurr.x, atlascurr.y, atlascurr.z];
        end
        
        % Get top anatomical label from MNI atlas.
        try
            mnilabel = lower(atlas_lookup(mniatlas, info.(subjcurr).allchan.mni.xyz(ichan,:), 'inputcoord', 'mni', 'queryrange', 3));
            mnilabel = mnilabel{1};
        catch
            mnilabel = 'NA'; % if no label or atlas was found.
        end
        info.(subjcurr).allchan.mni.region{ichan} = mnilabel;
        
        % Get top anatomical label from TAL atlas.
        try
            tallabel = lower(atlas_lookup(talatlas, info.(subjcurr).allchan.tal.xyz(ichan,:), 'inputcoord', 'tal', 'queryrange', 3));
            tallabel = tallabel{1};
        catch
            tallabel = 'NA'; % if no label or atlas was found.
        end
        info.(subjcurr).allchan.tal.region{ichan} = tallabel;
        
        % Get average anatomical annotations from Kahana group.
        avglabel = lower(info.(subjcurr).allchan.avg.region{ichan});
        
        % Get individual anatomical annotations from Kahana group.
        indlabel = lower(info.(subjcurr).allchan.ind.region{ichan});
        
        % Get labels corresponding to particular lobes.
        regions = {mnilabel, tallabel, indlabel};
        frontal = contains(regions, {'frontal', 'opercularis', 'triangularis', 'precentral', 'rectal', 'rectus', 'orbital'});
        temporal = contains(regions, {'temporal', 'fusiform'});
        nolabel = strcmpi('NA', regions);
        
        % Determine lobe location based on majority vote across three labels.
        if sum(frontal) > (sum(~nolabel)/2)
            info.(subjcurr).allchan.lobe{ichan} = 'F';
        elseif sum(temporal) > (sum(~nolabel)/2)
            info.(subjcurr).allchan.lobe{ichan} = 'T';
        else
            info.(subjcurr).allchan.lobe{ichan} = 'NA';
        end
    end
    info.(subjcurr).allchan.type = info.(subjcurr).allchan.type(:);
    info.(subjcurr).allchan.lobe = info.(subjcurr).allchan.lobe(:);
    for iatlas = 1:length(atlases)
        info.(subjcurr).allchan.(atlases{iatlas}).region = info.(subjcurr).allchan.(atlases{iatlas}).region(:);
    end
    
    % Get experiments performed.
    experiments = extractfield(dir([subjpathcurr 'experiments/']), 'name');
    experiments(contains(experiments, '.')) = [];
    
    % For each experiment...
    for iexp = 1:numel(experiments)
        expcurr = experiments{iexp};
        
        % ...get subject experiment path, ...
        exppathcurr = [subjpathcurr 'experiments/' expcurr '/sessions/'];
        
        % ...get session numbers, ...
        sessions = extractfield(dir(exppathcurr), 'name');
        sessions(contains(sessions, '.')) = [];
        
        % ...and get header file, data directory, and event file per session.
        for isess = 1:numel(sessions)
            info.(subjcurr).(expcurr).session(isess).headerfile = [exppathcurr sessions{isess} '/behavioral/current_processed/index.json'];
            info.(subjcurr).(expcurr).session(isess).datadir    = [exppathcurr sessions{isess} '/ephys/current_processed/noreref/'];
            info.(subjcurr).(expcurr).session(isess).eventfile  = [exppathcurr sessions{isess} '/behavioral/current_processed/task_events.json'];
        end
    end
    
    % Get sampling rate from sources.json file.
    sourcesfile = [exppathcurr sessions{isess} '/ephys/current_processed/sources.json'];
    try
        sources = loadjson(sourcesfile);
    catch
        info.(subjcurr).fs = 0; % if sources file not found.
        continue
    end
    sourcesfield = fieldnames(sources);
    info.(subjcurr).fs = sources.(sourcesfield{1}).sample_rate;
end

% Remove sessions with problems.
% info.R1156D.FR1.session(4) = [];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% >= 3 T/F channels
% clean line spectra 80-150Hz
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%  Subject - Sess - Temp - Front - Corr./All - Acc.     - Temp - Front - Corr./All - Acc.     - BAD - Notes
% 'R1020J' - 1    - 29T  - 32F   - 114/300   - 0.3800   - 17T  - 23F   - 104/283   - 0.3675   - :)  - Done. Core. 48.

% 'R1032D' - 1    - 14T  - 11F   - 95/300    - 0.3167   - 13T  - 11F   - 80/236    - 0.3390   - :)  - Done. Core. 19. 

% 'R1033D' - 1    - 18T  - 14F   - 23/108    - 0.2130   - 7T   - 13F   - 21/98     - 0.2143   - ??? - Done. Expansion? 31.

% 'R1034D' - 3    - 10T  - 55F   - 48/528    - 0.0909   - 8T   - 42F   - 41/485    - 0.0845   - ??? - Done. Expansion. 29. 
% 'R1034D' - 1/3  - 10T  - 55F   - 21/132    - 0.1667   - 8T   - 42F   - 21/136    - 0.1667   - ??? - 
% 'R1034D' - 2/3  - 10T  - 55F   - 24/300    - 0.0800   - 8T   - 42F   - 17/268    - 0.0634   - ??? - 
% 'R1034D' - 3/3  - 10T  - 55F   - 3/96      - 0.0312   - 8T   - 42F   - 3/81      - 0.0370   - ??? - 

% 'R1045E' - 1    - 17T  - 27F   - 98/300    - 0.3267   - 16T  - 25F   - 77/236    - 0.3263   - :)  - Done. Core. 51.

% 'R1059J' - 2    - 49T  - 59F   - 36/444    - 0.0811   - 24T  - 46F   - 35/418    - 0.0837   - ??? - Done. Expansion. 44. 
% 'R1059J' - 1/2  - 49T  - 59F   - 8/144     - 0.0556   - 24T  - 46F   - 8/135     - 0.0593   - ??? - 
% 'R1059J' - 2/2  - 49T  - 59F   - 28/300    - 0.0933   - 24T  - 46F   - 27/283    - 0.0954   - ??? - 

% 'R1075J' - 2    - 7T   - 83F   - 150/600   - 0.2500   - 7T   - 79F   - 134/560   - 0.2393   - :)  - Done. Core. 50.
% 'R1075J' - 1/2  - 7T   - 83F   - 102/300   - 0.3400   - 7T   - 79F   - 99/297    - 0.3333   - :)  - 105 recall (3 words repeated)
% 'R1075J' - 2/2  - 7T   - 83F   - 48/300    - 0.1600   - 7T   - 79F   - 35/263    - 0.1326   - :)  - 48 recall
 
% 'R1080E' - 2    - 6T   - 10F   - 107/384   - 0.2786   - 6T   - 7F    - 106/377  - 0.2812    - :)  - Done. Core. 43.
% 'R1080E' - 1/2  - 6T   - 10F   - 47/180    - 0.2611   - 6T   - 7F    - 47/176   - 0.2670    - :)  - 47
% 'R1080E' - 2/2  - 6T   - 10F   - 60/204    - 0.2941   - 6T   - 7F    - 59/201   - 0.2935    - :)  - 59

% 'R1120E' - 2    - 14T  - 4F    - 207/600   - 0.3450   - 8T   - 4F    - 207/599  - 0.3456    - :)  - Done. Core. 33.
% 'R1120E' - 1/2  - 14T  - 4F    - 97/300    - 0.3233   - 8T   - 4F    - 97/300   - 0.3233    - :)  - 97
% 'R1120E' - 2/2  - 14T  - 4F    - 110/300   - 0.3667   - 8T   - 4F    - 110/299  - 0.3679    - :)  - 112

% 'R1128E' - 1    - 8T   - 10F   - 141/300   - 0.4700   - 4T   - 9F    - 134/278  - 0.4820    - :)  - Done. Core. 26. 147 recall. 

% 'R1135E' - 4    - 6T   - 14F   - 107/1200  - 0.0892   - 6T   - 14F   - 38/503   - 0.0755    - ??? - Done. Core.
% 'R1135E' - 1/4  - 6T   - 14F   - 26/300    - 0.0867   - 6T   - 14F   - 18/199   - 0.0905    - ??? - 
% 'R1135E' - 2/4  - 6T   - 14F   - 43/300    - 0.1433   - 6T   - 14F   - 6/38     - 0.1579    - ??? - 
% 'R1135E' - 3/4  - 6T   - 14F   - 26/300    - 0.0867   - 6T   - 14F   - 7/112    - 0.0625    - ??? - 
% 'R1135E' - 4/4  - 6T   - 14F   - 12/300    - 0.0400   - 6T   - 14F   - 7/154    - 0.0455    - ??? -

% 'R1142N' - 1    - 18T  - 59F   - 48/300    - 0.1600   - 17T  - 56F   - 38/200   - 0.1900    - ??? - Done. Expansion. 50 recall. 
 
% 'R1147P' - 3    - 40T  - 32F   - 101/559   - 0.1807   - 9T   - 14F   - 75/430   - 0.1744    - :)  - Done. Core.
% 'R1147P' - 1/3  - 40T  - 32F   - 73/283    - 0.2580   - 9T   - 14F   - 54/213   - 0.2535    - :)  - 
% 'R1147P' - 2/3  - 40T  - 32F   - 11/96     - 0.1146   - 9T   - 14F   - 9/71     - 0.1268    - :)  - 
% 'R1147P' - 3/3  - 40T  - 32F   - 17/180    - 0.0944   - 9T   - 14F   - 12/146   - 0.0822    - :)  - 

% 'R1149N' - 1    - 39T  - 16F   - 64/300    - 0.2133   - 29T  - 16F   - 47/250   - 0.1880    - ??? - Done. Expansion. 67 recall.

% 'R1151E' - 3    - 7T   - 5F    - 208/756   - 0.2751   - 7T   - 5F    - 202/734  - 0.2752    - :)  - Done. Core.
% 'R1151E' - 1/3  - 7T   - 5F    - 77/300    - 0.2567   - 7T   - 5F    - 76/295   - 0.2576    - :)  - 
% 'R1151E' - 2/3  - 7T   - 5F    - 83/300    - 0.2767   - 7T   - 5F    - 81/296   - 0.2736    - :)  - 
% 'R1151E' - 3/3  - 7T   - 5F    - 48/156    - 0.3077   - 7T   - 5F    - 45/152   - 0.2961    - :)  -

% 'R1154D' - 3    - 39T  - 20F   - 271/900   - 0.3011   - 37T  - 19F   - 260/866  - 0.3002    - :)  - Done. Core.
% 'R1154D' - 1/3  - 39T  - 20F   - 63/300    - 0.2100   - 37T  - 19F   - 63/300   - 0.2100    - :)  - 
% 'R1154D' - 2/3  - 39T  - 20F   - 108/300   - 0.3600   - 37T  - 19F   - 103/281  - 0.3665    - :)  - 
% 'R1154D' - 3/3  - 39T  - 20F   - 100/300   - 0.3333   - 37T  - 19F   - 94/285   - 0.3298    - :)  - 

% 'R1162N' - 1    - 25T  - 11F   - 77/300    - 0.2567   - 17T  - 11F   - 75/276   - 0.2717    - :)  - Done. Expansion. 

% 'R1166D' - 3    - 5T   - 38F   - 129/900   - 0.1433   - 5T   - 35F   - 125/870  - 0.1437    - :)  - Done. Core. 
% 'R1166D' - 1/3  - 5T   - 38F   - 30/300    - 0.1000   - 5T   - 35F   - 30/295   - 0.1017    - :)  - 
% 'R1166D' - 2/3  - 5T   - 38F   - 49/300    - 0.1633   - 5T   - 35F   - 47/282   - 0.1667    - :)  - 
% 'R1166D' - 3/3  - 5T   - 38F   - 50/300    - 0.1667   - 5T   - 35F   - 48/293   - 0.1638    - :)  - 

% 'R1167M' - 2    - 39T  - 20F   - 166/372   - 0.4462   - 33T  - 18F   - 136/289  - 0.4706    - :)  - Done. Core. 33. Flat slope. 
% 'R1167M' - 1/2  - 39T  - 20F   - 80/192    - 0.4167   - 33T  - 18F   - 56/130   - 0.4113    - :)  - 
% 'R1167M' - 2/2  - 39T  - 20F   - 86/180    - 0.4778   - 33T  - 18F   - 80/159   - 0.5031    - :)  - 

% 'R1175N' - 1    - 34T  - 30F   - 68/300    - 0.2267   - 24T  - 27F   - 57/265   - 0.2151    - ??? - Done. Expansion. 73 recall. 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1020J %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1020J' - 1    - 29T  - 32F   - 114/300   - 0.3800   - 17T  - 23F   - 104/283   - 0.3675   - :)  - Done. 48.

% Some broken channels, big fluctuations and flat lines. 
% Some channels have extra line noise, but notches are effective.
% Notches are narrow, only at harmonics or above 150Hz. Baseline flat and clean.
% Remaining channels are relatively free of interictal events.
% Some buzz in remaining channels, somewhat slinky, but relatively low amplitude.
% Lots of surface channels. 
% Other than periods of extended slinkiness, nothing that could be easily taken out. [NOTE: I'm not taking slinkiness out anymore.]
% Great accuracy, high number of trials.
% No notes from researchers.

% 'RFB6', 'RFB7', 'RSTB2', 'RSTB3' have buzz along with others, but after buzz, continue little spikelets for a little while
% I stopped marking the artifacts at the end of buzz across channels, but let the spikelets continue. I could extend these. [NOTE: I extended some.]
% RSTB7 has big fluctuations, but only occassionally.
% Channels are very slinky.
% Very little evidence of interictal spikes in surface, and not many in depths either.
% Buzz was removed if across multiple channels, not as much if only in one channel.

% Clean subject, great subject. Only concern are the buzzy channels I did not remove (RFB6, RFB7, RSTB2, RSTB3). [NOTE: looking at these channels, don't seem bad]
% A great pilot subject for phase encoding.
% Slightly careful with HFA and slope.

% Channel Info:
info.R1020J.badchan.broken = {'RSTB5', 'RAH7', 'RAH8', 'RPH7', 'RSTB8', 'RFB8', ... % my broken channels, fluctuations and floor/ceiling. Confirmed.
    'RFB4', ... % one of Roemer's bad chans
    'RFB1', 'RFB2', 'RPTB1', 'RPTB2', 'RPTB3'}; % Kahana broken channels

info.R1020J.badchan.epileptic = {'RAT6', 'RAT7', 'RAT8', 'RSTA2', 'RSTA3', 'RFA1', 'RFA2', 'RFA3', 'RFA7', ... % Kahana seizure onset zone
    'RSTB4', 'RFA8' ... % after buzzy episodes, continue spiky (like barbed wire)
    'RAT*' ... % synchronous little spikelets, intermittent buzz. Also very swoopy. Confirmed confirmed.
    }; 

info.R1020J.refchan = {'all'};

% Line Spectra Info:
% Session 1/1 z-thresh 0.45, 1 manual (tiny tiny peak), using re-ref. Re-ref and non-ref similar spectra.
info.R1020J.FR1.bsfilt.peak      = [60  120 180 219.9 240 300 ...
    190.3];
info.R1020J.FR1.bsfilt.halfbandw = [0.5 0.5 0.7 0.5   0.5 0.8 ...
    0.5];
info.R1020J.FR1.bsfilt.edge      = 3.1840;

% Bad Segment Info:
% Focused primarily on removal of buzzy episodes, also on some episodes where RSTB7 has big fluctuations
info.R1020J.FR1.session(1).badsegment = [499311,500554;508251,508716;553916,554937;578019,580740;668182,668792;937194,938417;948517,950659;1023532,1024720;1049122,1049977;1061343,1062002;1153784,1157155;1218605,1221167;1335219,1337563;1470021,1472000;1541100,1543946;1669122,1669848;1770421,1773973;1840485,1842900;1940356,1941288;1942113,1943574;1944162,1947058;1948727,1949010;1951509,1953930;2040513,2042489;2282545,2283013;2296392,2297288;2323413,2326543;2340670,2342784;2478525,2479570;2553863,2554364;2556896,2557381;2573988,2574872;2650561,2651735;2653851,2655606;2963848,2967067;3230319,3232379];

% Likely over prioritizes larger slinky fluctuations, definitely misses buzzy episodes.
% info.R1020J.FR1.session(1).badsegment = [1,2146;20947,21937;46669,47299;85793,86138;98094,98896;148350,149144;151454,152000;264839,265442;268001,268561;272001,272601;301702,302329;308251,309974;447347,448000;572001,572918;578266,580000;598812,600000;630943,632000;641025,645614;668205,668733;687666,688000;800001,800819;887763,888542;891196,892000;948651,950399;982014,983584;996001,998369;1154204,1156000;1218384,1219810;1226164,1227434;1236001,1236424;1280001,1281224;1284001,1284743;1390989,1391356;1541589,1543262;1669151,1669786;1770680,1773028;1840772,1842587;1853546,1854853;1940377,1941165;1945269,1946950;1952001,1953684;2040261,2042127;2108068,2108899;2180001,2180725;2282586,2282716;2296264,2297015;2324001,2326076;2340777,2342783;2574043,2574783;2652423,2653087;2653858,2655576;2918344,2919049;2964001,2966772;3076259,3076840;3167062,3167759;3230511,3232383];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1032D %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1032D' - 1    - 14T  - 11F   - 95/300    - 0.3167   - 13T  - 11F   - 80/236    - 0.3390   - :)  - Done. 19.

% Mostly depth electrodes. 
% Lots of reference noise and flat-line channels.
% Only narrow lines at harmonics. Re-ref cleans baseline. Re-ref and non-ref very similar.
% Noise is consistent across channels.
% Mild slink, but low amplitude. 
% Channels LFS1-4 have periodic synchronous dips. Occasionally RFS1-3 as well. Big dips were marked for rejection.
% Consider removing these channels from analyses to see if results hold. 
% Slink periods relatively short. 
% Perhaps more dips in LFS1-4 could be removed. 
% Great accuracy, decent number of trials.
% No researcher notes.
% Removing deflections from surface channels if the deflections are reflected in the depths.
% Very little, if any buzz.
% Channel RFS8 gets spiky between segments 281 and 292.
% Interictal spikes in surface channels.
% Checked for spikes in depths that extended to surface.

% Data is very clean of buzz. 
% Synchronous dips in LFS, RFS are a little worrying for phase encoding.
% B/c of synchronous dips and middling coverage, would be an interesting test subject for phase encoding.
% Great for HFA and slope.

% Channel Info:
info.R1032D.badchan.broken = {'LFS8', 'LID12', 'LOFD12', 'LOTD12', 'LTS8', 'RID12', 'ROFD12', 'ROTD12', 'RTS8', ... % flat-line channels
    };

info.R1032D.badchan.epileptic = {};

info.R1032D.refchan = {'all'};

% Some channels show large epileptic deviations, but are kept in to prioritize channels: 'LFS1x', 'LFS2x', 'LFS3x', 'LFS4x'

% Line Spectra Info:
% Session 1/1 z-thresh 1 re-ref, no manual. 
info.R1032D.FR1.bsfilt.peak      = [60   120  180  240  300];
info.R1032D.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5];
info.R1032D.FR1.bsfilt.edge      = 3.2237;

% Bad Segment Info:
% Added and removed some deflections, added presence of spikes in surface from depths.
info.R1032D.FR1.session(1).badsegment = [295956,297228;318272,319731;323646,324666;347892,349415;380137,381092;382349,383266;401996,403228;411943,412718;423518,424112;428364,429396;437737,438531;455672,456196;498245,499870;506647,508486;510769,511531;575342,576101;604775,605989;642569,642789;693279,694441;771524,772286;811091,811653;815633,816409;852995,853531;860491,861550;890292,891260;920736,923506;926162,927795;959791,960559;966378,966972;976543,977254;985493,986278;989072,989834;992498,993415;1010691,1011169;1034124,1035563;1050131,1051189;1063330,1064035;1082311,1082983;1104014,1105318;1127421,1127764;1197318,1199234;1206072,1206718;1213672,1214305;1226994,1228208;1234642,1235747;1259820,1260782;1283646,1284982;1297923,1298827;1300111,1301789;1312318,1313306;1327098,1327725;1366911,1367815;1384272,1385041;1395253,1396254;1399046,1399763;1429292,1430092;1536718,1538867;1541523,1542202;1611640,1612247;1634466,1636086;1686033,1686950;1699588,1700131;1708460,1710030;1787672,1788725;1837040,1837738;1838892,1840138;1864285,1865093;1923091,1924028;1936795,1938195;1942878,1943705;1984382,1986067;2001414,2002124;2004047,2005609;2006246,2008679;2017105,2017473;2028056,2029115;2060252,2060531;2071556,2072769;2075124,2075815;2102575,2103537;2134085,2134480;2140562,2143208;2154046,2155234;2218188,2218937;2275840,2276383;2296136,2296769;2302240,2303731;2379240,2380105;2490021,2490486;2491234,2491873;2575782,2576976;2683169,2684047;2769040,2770731;2773872,2774402;2787653,2788899;2836318,2837015;2873924,2874473;2878446,2878970;2909427,2910299;2954453,2954673;3007272,3007944;3031504,3032144;3037711,3038208;3048930,3049770;3104111,3104751;3189285,3190144;3240588,3241376;3250570,3251785;3282078,3282602;3343072,3343667;3351188,3351808;3369575,3370196;3386492,3387054;3392214,3393009;3418892,3419667;3454246,3455021;3478498,3479073;3482918,3484080;3484956,3485531;3493789,3494465;3507201,3507783;3564590,3566094;3585137,3587221;3596424,3597255;3625111,3625738;3649853,3650396;3679416,3680366;3718348,3719571;3723743,3724473;3734614,3735350;3813557,3814279;3817580,3818101;3831169,3831828;3843285,3844060;3914453,3915131;3930743,3931893;3987918,3988338;4040356,4040506;4062736,4063511;4065769,4065983;4074446,4075021;4081124,4082815;4084260,4084738;4097917,4098209];

% info.R1032D.FR1.session(1).badsegment = [6692,7487;13550,14138;16620,17202;22614,23776;50403,51060;76023,79445;105550,106673;109098,109835;111814,112641;130627,131144;200285,200602;201414,201744;209220,209679;212756,215299;219092,219596;250892,251686;259595,260415;266788,267557;292356,292866;296059,297176;318349,319531;323672,324570;344181,344550;348124,349557;357439,357969;382427,383111;402069,403201;412014,412654;428382,429360;437782,438486;455788,456189;498574,499487;506866,508486;510852,511511;527982,528376;539098,539647;575342,575946;594846,595189;605395,605879;687833,688131;693808,694351;751459,751996;771666,772157;811162,811570;815672,816009;853027,853512;860537,861467;890382,891183;920767,921644;922143,923377;926197,927739;959846,960559;966434,966932;976575,976783;985539,986278;989088,989801;992511,993370;1010723,1011118;1024866,1025486;1032666,1033118;1034453,1035479;1050156,1051189;1063382,1063970;1090143,1090564;1104091,1105002;1115866,1116480;1135117,1135602;1138098,1138711;1154001,1154299;1181962,1182273;1197356,1199254;1206098,1206660;1219466,1220537;1227027,1228215;1234660,1235756;1259834,1260701;1283666,1284976;1297917,1298827;1300150,1301783;1312337,1313286;1324249,1325135;1327095,1327735;1366917,1367795;1384279,1385041;1395261,1396202;1399066,1399742;1429305,1430067;1458581,1459163;1511801,1512254;1611640,1611963;1629491,1629983;1634472,1636021;1672382,1672989;1686053,1686925;1687782,1688421;1699608,1700131;1708478,1710021;1787685,1788615;1837124,1837667;1838898,1839673;1847517,1848047;1864324,1865015;1923291,1924008;1936943,1938131;1943014,1943686;1984324,1985699;2004072,2005589;2006749,2008441;2016995,2017422;2028111,2028933;2071556,2072782;2075137,2075809;2102608,2102892;2118995,2119428;2140582,2143137;2154072,2154989;2218195,2218847;2272692,2273254;2296201,2296718;2303175,2303692;2317305,2317731;2328414,2329008;2379246,2380066;2472246,2472654;2474717,2475183;2476308,2477066;2491943,2492247;2535408,2535944;2575827,2576931;2580060,2580602;2667614,2667969;2673117,2673512;2683556,2683970;2767698,2767918;2769078,2770544;2772756,2773260;2785505,2785828;2787685,2788815;2878446,2878899;2909582,2910189;2923723,2924157;2971337,2971667;3007279,3007918;3023311,3023705;3029117,3029422;3031582,3032099;3037782,3038150;3049182,3049680;3086814,3087305;3088349,3088757;3189324,3190022;3240685,3241351;3250588,3251730;3282104,3282557;3343092,3343641;3351233,3351770;3369608,3370157;3386537,3387054;3398795,3399228;3419001,3419635;3454278,3454963;3478511,3478731;3484966,3485505;3493789,3494401;3507260,3507744;3564608,3566032;3585930,3587228;3596461,3597228;3607814,3608350;3625130,3625692;3649872,3650376;3679434,3680338;3707879,3708415;3734652,3735319;3817627,3818086;3828221,3828570;3843317,3844054;3852334,3852845;3914459,3914957;3919034,3919531;3930769,3931860;3956750,3957409;3958993,3959925;3973306,3974688;3987943,3988331;4037685,4038156;4062788,4063505;4081136,4081505;4082252,4082757;4084305,4084635;4116272,4117396;4165427,4166279;4174601,4175015;4236783,4237139;4256169,4256577;4264356,4264789;4270492,4270970];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1033D %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1033D' - 1    - 18T  - 14F   - 23/108  - 0.2130   - 7T   - 13F   - 21/98   - 0.2143   - !!! - Too few correct trials.

% Removed buzz and IED events, lots of large and some small blips that carry through from depths.
% Remaining surface channels have frequent slow drifts.
% Even if this subject had ended up with enough trials, I would not trust them. [EDIT: maybe not that bad].
% LTS6 and LTS7 were originally marked as broken/epileptic (high frequency noise/spiky slinkies). New cleaning kept them in.
% Stopped because patient was having trouble focusing.
% Prioritizing trials over channels.
% Not that bad of a subject, really.
% I'm guessing not too many ambiguous events remain. 
% Very clean lines.

% Channel Info:
info.R1033D.badchan.broken = {'LFS8', 'LTS8', 'RATS8', 'RFS8', 'RPTS8', 'LOTD12', 'RID12', 'ROTD12'... % flat-line channels
    'LOTD6'}; % large voltage fluctuations; might be LOTD9

info.R1033D.badchan.epileptic = {'RATS*' ... % Kahana
    'RPTS*' ... % IED bleedthrough from depths. Prioritizing trials over channels.
    };

info.R1033D.refchan = {'all'};

    
% Line Spectra Info:
info.R1033D.FR1.bsfilt.peak      = [60.1 120 180 240 300];
info.R1033D.FR1.bsfilt.halfbandw = [0.5  0.5 0.5 0.5 0.5];
info.R1033D.FR1.bsfilt.edge      = 3.2225;

% Bad Segment Info:
info.R1033D.FR1.session(1).badsegment = [414945,420783;538621,538680;594181,598247;696949,699215;711098,715176;808988,813267;1176724,1181432;1336700,1339307;1387536,1392086;1395569,1399163;1402653,1406015;1618472,1621609;1637556,1639125;1656427,1660183];
% info.R1033D.FR1.session(1).badsegment = [373498,373841;389756,390079;411782,420783;468266,472453;536149,536557;538621,538680;540524,541196;564189,564596;593046,593402;594181,598247;619388,619718;696949,699215;711098,715176;776453,776738;808988,813267;870802,871125;878698,879080;934401,935873;940220,940647;1020311,1020854;1052988,1054647;1101666,1102119;1157633,1160615;1176724,1181432;1273200,1274195;1279970,1280601;1336700,1339307;1376001,1376312;1379904,1380466;1387536,1392086;1395569,1399163;1402653,1406015;1426762,1427557;1441795,1443073;1466202,1467028;1518027,1519667;1528278,1529389;1531904,1533209;1579530,1580408;1604414,1604886;1618472,1621609;1637556,1639125;1656427,1660183;1675730,1676800;1678227,1680344;1703369,1704364];
% info.R1033D.FR1.session(1).badsegment = [16033,16621;29788,31234;140336,142280;154518,157163;160621,167783;268046,269209;299057,307744;335556,341047;411672,419679;468272,472421;540537,542202;594175,598234;696949,699215;711111,715118;809001,812800;934401,935867;1053008,1054621;1157639,1160609;1176852,1179138;1273200,1274168;1280001,1280551;1336730,1338215;1387533,1391785;1395576,1399041;1402679,1405976;1426766,1427542;1441969,1443183;1518047,1519647;1528291,1529331;1531937,1533189;1618497,1621570;1637601,1639099;1656433,1660183;1678240,1680299;1703401,1704338;1729743,1730415;1734401,1735467;1792105,1795873;1808420,1811200;1811215,1817600;1852285,1855557;1913601,1914841;1917575,1920000];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1034D %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1034D' - 3    - 10T  - 55F   - 48/528    - 0.0909   - 8T   - 42F   - 41/485    - 0.0845   - ??? - Done. 29. Expansion.
% 'R1034D' - 1/3  - 10T  - 55F   - 21/132    - 0.1667   - 8T   - 42F   - 21/136    - 0.1667   - ??? - 
% 'R1034D' - 2/3  - 10T  - 55F   - 24/300    - 0.0800   - 8T   - 42F   - 17/268    - 0.0634   - ??? - 
% 'R1034D' - 3/3  - 10T  - 55F   - 3/96      - 0.0312   - 8T   - 42F   - 3/81      - 0.0370   - ??? - 

% Line spectra relatively clean.
% Channels are ropy in Session 1, need LP to clean.
% RIHG grid is very flat compared to others. Need to go through it separately to clean.
% Big deflections in LTS channels that are sometimes present in other channels, but being lenient in order to preserve trials.
% Not many IEDs or buzz, just wonkiness.
% Removing big deflections if in multiple grids (like in all of LTS, LFG, and RIHG)
% Session 2: more blips across grids, not necessarily big, but definitely more IED looking.
% This subject's IEDs are very subtle
% Lots of IEDs in Session 3 too. Very poor performance in Session 3.
% Looking at Session 1 again. Not many IEDs.
% LIHG17-18 are marked as epileptic by me, but could probably be kept in. That being said, we don't really need two more frontal channels.
% Same thing for LOFG10.
% So, I'm leaving them out.
% Only notes about two of three sessions. The first note says that the subject was not feeling good.

% A somewhat ambiguous subject, with large fluctuations (especially in LTS) that may or may not affect phase encoding.
% High frontal coverage, so interesting test subject for phase encoding.
% Great for HFA and slope. 

% Channel Info:
info.R1034D.badchan.broken = {'LFG1', 'LFG16', 'LFG24', 'LFG32', 'LFG8', 'LIHG16', 'LIHG24', 'LIHG8', 'LOFG12', 'LOFG6', 'LOTD12', 'LTS8', 'RIHG16', 'RIHG8', ... % flat-line channels
    'LOTD7'}; % large voltage fluctuations

info.R1034D.badchan.epileptic = {'LIHG17', 'LIHG18'... % big fluctuations and small sharp oscillations. Confirmed.
    'LOFG10', ... % frequent small blips, removed during second cleaning. Confirmed.
    'LFG13', 'LFG14', 'LFG15', 'LFG22', 'LFG23'}; % marked by Kahana

info.R1034D.refchan = {'all'};

% Line Spectra Info:
% Combined re-ref, has spectra for all sessions. z-thresh 1 + manual
info.R1034D.FR1.bsfilt.peak      = [60  120 172.3 180 183.5 240 300 305.7 ...
    61.1 200 281.1 296.3 298.1];
info.R1034D.FR1.bsfilt.halfbandw = [0.5 0.5 0.5   0.5 0.5   0.6 0.9 0.5 ...
    0.5  0.5 0.5   0.5   0.5];
info.R1034D.FR1.bsfilt.edge      = 3.2237;
     
% Bad Segment Info:
info.R1034D.FR1.session(1).badsegment = [418859,420105;443382,444751;576389,580731;927897,929035;1065949,1066828;1119020,1122286;1157962,1158977;1214827,1215892;1416659,1419518;1547646,1548234;1552020,1561253];
info.R1034D.FR1.session(2).badsegment = [446407,448990;452969,454932;520027,521467;600181,601137;618395,619408;620442,621784;683201,683660;690562,691086;735233,735602;736563,737054;790337,790860;849659,850647;973789,974886;1073716,1081380;1104836,1108258;1229213,1230936;1370015,1370627;1444275,1445070;1493901,1494632;1693569,1694092;1734660,1735848;1765949,1769447;1771052,1772595;1890633,1891421;2028786,2030712;2056840,2058009;2083801,2084241;2099369,2099809;2193910,2194466;2244104,2244679;2246119,2246950;2259324,2259951;2409511,2410021;2436324,2437769;2440563,2441421;2509285,2510215;2694847,2696712;2745853,2747196;2748401,2749092;2750285,2751505;2790666,2791583;2937601,2943408;3079705,3080918;3112034,3112725;3123201,3124235;3193472,3194713;3200298,3201067;3342511,3346956;3378279,3379612;3428040,3428853;3491324,3492415;3571679,3572615;3628294,3629335;3692054,3698287;3731285,3732454;3772982,3773983;3775820,3777053;3790388,3791505;3796498,3797525;3860995,3863402;3871085,3872000;4015337,4016286;4017201,4018021;4027408,4027905;4134866,4136131;4301679,4302512;4312027,4313040];
info.R1034D.FR1.session(3).badsegment = [334698,335280;337994,339200;356885,357847;376207,377460;425917,426750;475356,476105;514240,515241;516033,517182;521633,522744;523575,524621;527524,528376;570118,570938;571808,575021;600027,600731;659344,660473;663261,666830;668150,669692;672608,674589;749679,750680;819201,820873;858672,862415;868897,870569;972245,973578;977730,978724;1006576,1007434;1017918,1018751;1031201,1032486;1061788,1062866;1082782,1083654;1087343,1087711;1123820,1124466;1175814,1176898;1185298,1188208;1250105,1251034;1307872,1310615;1335620,1336737;1337177,1338529;1380414,1382376;1403666,1404234;1406710,1407079;1408885,1412931;1425388,1427200;1428892,1429609;1433354,1434687];

% info.R1034D.FR1.session(1).badsegment = [76801,77572;93764,94659;102208,102963;161824,162333;166173,166941;208310,208857;220358,221472;330990,331360;362431,363606;364801,365654;371201,371950;383154,384353;403812,404492;668336,669120;712323,712858;722060,723055;765115,766006;858349,858909;911304,912126;915704,916527;934152,935017;1417355,1418204;1562986,1563576;1626014,1626535;1762697,1763300;1994383,1995283;2144001,2144363;2265601,2268402;2272607,2273451;2280740,2281627;2324272,2325357;2446530,2447116;2558091,2559627;2572438,2573874;2608886,2609494;2634981,2636251;2641696,2643693;2680362,2680874;2682126,2682944;2694091,2695192];
% info.R1034D.FR1.session(2).badsegment = [84629,85886;129373,129967;401329,402049;414413,414986;502327,502931;520018,521365;683230,683717;690585,690999;917209,917584;1222814,1223813;1307549,1308574;1436543,1438259;1448379,1450724;1562560,1563193;1789871,1791494;1875795,1877283;1956555,1958400;2037820,2039184;2083841,2084014;2158444,2159593;2189266,2189886;2244031,2244659;2270043,2271193;2387911,2388609;2399484,2400115;2402982,2403479;2764020,2764660;2802869,2803882;2817291,2818120;2827149,2828800;2838059,2839499;2934685,2935299;2953382,2953860;3067240,3068847;3071147,3072817;3123254,3124058;3174120,3175580;3256558,3258791;3335795,3336731;3649988,3650776;3790382,3791202;3833601,3838892;3862046,3863202;3956795,3958054;3985833,3987098;4262401,4263519;4462872,4464067;4495866,4496925];
% info.R1034D.FR1.session(3).badsegment = [306485,307734;376117,377389;405640,408253;570137,570622;571872,572312;572949,573454;574207,574686;606594,608000;953731,955641;1116479,1118195;1380465,1382060];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1045E %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: 
% FINISHED FINISHED

% 'R1045E' - 1    - 17T  - 27F   - 98/300    - 0.3267   - 16T  - 25F   - 77/236    - 0.3263   - :)  - Done. Core. 51.

% End of segment goes bad. Samples 2603373 onward are bad.
% Enormous spikes in several channels, screwing up demeaning. 
% Will have to clean lines around spikes. 
% Spikes are at samples 431722:431752, 1078427:1078454, and 2204508:2204508
% Clean is [1:431721, 431753:1078426, 1078455:2204507, 2204534:2603373]
% Less spikes in re-ref vs. non-ref (3 vs. 9). Baselines similar. 
% Noise consistent across channels.
% LATS1-4 are coherent, strongly slinky, high amplitude. [NOTE: now removing.]
% Reference buzz remains in surface channels.
% LAFS and remaining LATS are very smooth and flat, whereas other surface channels have more high frequency activity.
% No more discrete events to remove (other than buzz), but does not look very clean.
% Right-hand channels have odd-number naming convention. Keeping them in, but consider removing them.
% 'RPTS7' was originally marked as broken, but keeping in. [NOTE: apparently taking it out]
% Removing buzzy episodes.
% Subject attentive and engaged.

% Buzz is main concern, but these seem mostly discrete. Not great for slope, but not awful. Would be ok.
% But great coverage for phase encoding, though watch out for LATS1-4

% Channel Info:
info.R1045E.badchan.broken = {'RPHD1', 'RPHD7', 'LIFS10', 'LPHD9', ... % large fluctuations
    'RAFS7', ... % very sharp spikes
    'RPTS7' ... % periodic sinusoidal bursts
    };

info.R1045E.badchan.epileptic = {'LAHD2', 'LAHD3', 'LAHD4', 'LAHD5', ... % Kahana
    'LMHD1', 'LMHD2', 'LMHD3', 'LMHD4', 'LPHD2', 'LPHD3', 'LPHGD1', 'LPHGD2', 'LPHGD3', ... % Kahana
    'LPHGD4', 'RAHD1', 'RAHD2', 'RAHD3', 'RPHGD1', 'RPHGD2', 'RPHGD3', ... % Kahana
    'LATS1', 'LATS2', 'LATS3', 'LATS4', 'LATS5' ... % constant coherent high amplitude slink with IEDs
    }; 

info.R1045E.refchan = {'all'};

% Line Spectra Info:
% Session 1/1 z-thresh 2 on re-ref, no manual. 
info.R1045E.FR1.bsfilt.peak      = [59.9 179.8 299.6];
info.R1045E.FR1.bsfilt.halfbandw = [0.5  0.5   0.5];
info.R1045E.FR1.bsfilt.edge      = 3.1852;
     
% Bad Segment Info:
% Have to remove sample 2603373 onward b/c of file corruption.
% Added bad segments of big spikes.
info.R1045E.FR1.session(1).badsegment = [426456,427376;430634,432786;489664,492021;573918,575147;603046,604538;668795,670121;763031,763858;777706,778508;878339,879120;889324,892020;960986,961515;983367,984697;1052995,1054103;1077390,1079768;1117845,1119861;1197221,1199374;1271357,1273408;1354645,1355991;1433457,1434735;1460994,1463412;1559206,1561104;1581212,1582413;1610941,1613273;1635295,1637809;1657760,1659643;1693909,1694523;1754297,1756481;1777092,1778705;1848710,1848868;1852916,1854144;1955418,1959202;1986013,1986985;2021977,2023589;2121877,2125386;2160249,2161836;2202546,2205761;2241007,2242652;2317358,2318906;2346414,2349258;2355489,2359704;2360718,2364755;2366930,2369073;2410999,2411604;2436867,2439423;2444171,2444981;2463933,2465227;2500654,2502823;2503692,2504760;2603221,2916214];
% info.R1045E.FR1.session(1).badsegment = [426456,427376;430634,432786;489664,492021;573918,575147;603046,604538;668795,670121;763031,763858;878339,879120;889324,892020;960986,961515;983367,984697;1052995,1054103;1077390,1079768;1117845,1119861;1197221,1199374;1271357,1273408;1354645,1355991;1433457,1434735;1460994,1463412;1559206,1561104;1581212,1582413;1610941,1613273;1635295,1637809;1651384,1653495;1657760,1659643;1693909,1694523;1754297,1756481;1777092,1778705;1848710,1848868;1852916,1854144;1955418,1959202;1986013,1986985;2021977,2023589;2121877,2125386;2160249,2161836;2202546,2205761;2241007,2242652;2317358,2318906;2346414,2349258;2355489,2359704;2360718,2364755;2366930,2369073;2410999,2411604;2436867,2439423;2444171,2444981;2463933,2465227;2500654,2502823;2503692,2504760;2603221,2916214];
% info.R1045E.FR1.session(1).badsegment = [171293,172850;302034,303412;379153,380800;384913,386115;426457,427358;430641,432517;489846,491741;573928,575086;603397,604300;623377,623925;668820,670096;763042,763823;878373,879120;889330,891384;960993,961455;983374,984663;1053011,1054077;1077440,1079687;1117865,1119832;1197280,1199336;1258278,1258740;1266733,1267088;1271811,1273616;1354645,1355644;1434161,1434641;1438561,1438623;1461991,1463351;1559450,1560847;1581226,1582347;1611315,1612935;1635678,1637096;1658341,1659574;1693987,1694304;1754752,1756251;1777132,1778646;1848757,1848828;1853043,1854083;1955661,1959014;1986013,1986790;2021977,2023548;2121877,2125336;2160321,2161836;2203502,2205522;2241090,2242587;2317681,2318718;2346544,2348846;2355903,2358552;2360828,2362948;2367601,2368912;2411103,2411472;2437117,2438888;2444287,2444916;2464552,2464966;2500943,2502743;2503969,2504623;2573425,2573538;2603373,2916214;431722, 431752; 1078427, 1078454; 2204508, 2204508];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1059J %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% LFB3 was marked as broken, but not sure why I did that.
% IEDs in depths/epileptic channels bleed into LSTA, LSTB
% 'Patient spoke words aloud during list 1 presentation, had no recall for several lists. Did not seem to understand instructions and had poor recall on most lists. Patient completed 12 lists.'
% 'Offered strategy after list 12 (had several lists with no recall).'
% RSTA and RSTB are slightly buzzy.
% Removing buzzy episodes.
% Several strong IED episodes in depths, hoping I removed enough of the bad surface channels to compensate.
% LFB grid has slow swoops that follow depth IEDs.
% Buzz is more ambiguous in Session 2.
% Long buzz episodes in Session 2.
% Really prioritizing trials over channels b/c of low trial number. 

% Buzz is concerning.
% Great coverage for phase encoding, and considering how many channels I threw out, I'm confident in what remains.

% 'R1059J' - 2    - 49T  - 59F   - 36/444  - 0.0811   - 24T  - 46F   - 35/418  - 0.0837   - ??? - Done. Expansion. 44. 
% 'R1059J' - 1/2  - 49T  - 59F   - 8/144   - 0.0556   - 24T  - 46F   - 8/135   - 0.0593   - ??? - 
% 'R1059J' - 2/2  - 49T  - 59F   - 28/300  - 0.0933   - 24T  - 46F   - 27/283  - 0.0954   - ??? - 

% Channel Info:
info.R1059J.badchan.broken = {'LDC*', 'RDC7', 'LFC1', 'LIHA1', 'RAT1', 'RAT8', 'RIHA1', 'RIHB1', ... % big fluctuations. Confirmed.
    };

info.R1059J.badchan.epileptic = {'LSTA8', ... % continuously spiky. Confirmed.
    'LSTA1', 'LSTA2', 'LSTA3', 'LSTA4', 'LSTA5', 'LSTB*', 'LPT5', 'LPT6', 'RPT1', ... % IEDs bleeding through. Removing to preserve trials. Confirmed.
    'LAT5', 'LAT6', 'LAT7', ... % strong slink that is accompanied by spikes in depths
    'RAT2', 'RAT3', 'RAT6', 'RAT7', 'RSTA2', 'RSTA3', 'RSTA5', 'RSTA6', 'RFB1', 'RFB2', ... % little spikelets with one another
    'LFB5', 'LFB6', 'LFB7', 'LFB8', ... % swoops that track depths
    'LFD1', ... % swoops with spiky oscillations atop (Session 2)
    'RPT8', 'RPTA8', 'RPTB8', ... % intermittent buzz (especially in Session 2)
    'RIHA2', 'RFC1', 'RFC3', ... % break (mildly) partway through Session 2, big swoops
    'LAT1', 'LAT2', 'LAT3', 'LAT4'}; % Kahana

info.R1059J.refchan = {'all'};

% Line Spectra Info:
info.R1059J.FR1.bsfilt.peak      = [60  180 240 300];
info.R1059J.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5];
info.R1059J.FR1.bsfilt.edge      = 3.1840;

% Bad Segment Info:
info.R1059J.FR1.session(1).badsegment = [464001,464961;560170,562393;670669,672979;792582,794626;967811,969215;988178,988349;989178,990163;1093601,1094389;1172964,1174707;1334311,1336000;1387387,1388000;1435101,1435312;1491812,1493448];
info.R1059J.FR1.session(2).badsegment = [456154,458167;761303,763116;878336,881296;1154089,1164000;1164005,1170590;1425069,1428000;1469013,1473131;1546379,1547038;1657702,1664000;1960908,1961066;1968001,1971094;2089573,2094957;2162383,2162522;2392001,2397473;2411206,2414417;2470371,2470844;2521593,2523469];

% info.R1059J.FR1.session(1).badsegment = [1,1880;26479,26533;53245,54052;61729,62197;70339,71071;78957,79810;81710,81875;82726,82867;89143,89203;89809,89896;102479,102531;125086,125211;140917,141095;143357,143514;149395,149520;149651,149808;150325,150480;190570,190756;200202,200410;209836,210251;212001,212160;219212,219976;234355,235565;255548,255673;284783,285719;291507,292192;343161,343482;348737,349058;438067,438434;469094,469259;486782,487168;498014,498939;502231,502367;560616,562007;586035,587503;593154,594845;598169,599345;650624,651264;691307,693972;728697,731761;734943,736000;774809,775987;776001,776389;796554,797324;842124,842488;843296,844000;844275,844622;855038,855237;882900,883442;957460,957611;988186,988343;989189,990165;991626,992037;1018925,1019025;1034777,1035759;1064372,1067275;1068487,1068864;1097925,1099423;1100148,1100475;1184377,1186173;1197293,1197410;1299302,1303415;1385903,1386996;1387403,1388027;1388506,1388870;1391623,1392301;1430089,1430786;1435110,1435315;1455705,1456744;1458517,1459513;1460028,1460260;1490395,1490807;1500487,1500741;1507317,1507874;1508237,1508553;1509232,1509770;1511486,1511990;1513726,1518125;1522804,1525853;1539239,1539482;1566250,1567627;1568001,1570447;1581355,1582283;1621842,1622649;1647129,1647909;1657417,1658146;1667521,1667614;1689038,1689122;1774441,1774821;1776124,1776504;1779674,1780090;1788218,1788808;1823070,1823159;1864498,1864585;1865586,1865708;1908173,1908235;1916750,1916837;1944119,1944238;1947666,1948085;1953129,1953434;1954893,1955061;1955779,1956202;2043406,2044593;2045728,2045957;2046796,2048000;2059571,2061085;2063110,2063662;2083290,2083990;2086659,2086775;2099908,2100464;2101605,2101764;2102718,2102915;2120710,2120929;2143391,2143943;2184476,2184800;2194694,2195006;2233863,2234850;2237272,2237998;2240001,2242848;2246973,2247616;2273680,2274227;2281758,2282340;2300194,2300668;2301976,2302477;2303185,2303455;2318135,2318582;2328498,2329227;2335258,2335729;2335892,2336894;2339067,2339568;2356904,2361235;2363851,2364626;2367634,2368589;2395865,2396509;2423309,2423622;2463704,2464278;2470309,2471315;2471791,2472165;2474695,2477766;2484315,2485439;2486849,2487544;2488699,2490063;2514140,2514488;2553726,2554759;2559546,2560892;2568793,2571079;2592979,2593568;2600001,2601337;2605492,2606023;2623425,2624000;2682793,2683377;2728181,2728741;2742261,2743899;2744001,2744438;2766274,2768959;2770505,2771175;2789119,2789544;2822669,2823135];
% info.R1059J.FR1.session(2).badsegment = [1,1744;3270,3324;6013,6135;27597,27622;41863,43203;43960,43989;44001,45195;48001,56000;63383,65385;66355,66518;67331,67537;89839,90026;102710,103279;108078,108304;109787,110288;119836,121302;161876,162211;167675,169118;171557,172000;173851,174046;184973,185671;242295,243638;244005,248000;254581,255562;270654,271348;279760,280639;281459,282595;337380,337744;362424,363316;364977,365530;372243,373139;419262,420000;438436,438965;469674,470207;614472,614820;654065,654530;673589,674522;679673,679860;706956,707574;752243,752744;785142,785848;793114,793518;814988,815537;817460,818179;839621,840106;887809,890502;994476,995231;996997,997429;1000682,1001627;1046541,1046981;1060001,1060425;1075892,1076589;1129549,1130606;1132561,1134925;1137803,1138344;1139755,1140007;1154166,1160000;1160005,1164000;1164009,1170175;1183581,1184000;1205057,1205643;1225295,1225647;1274847,1275779;1340573,1341312;1362670,1365405;1405146,1405655;1417956,1418296;1469077,1472000;1475129,1476000;1494057,1494731;1546400,1547005;1549343,1550320;1564182,1564893;1608162,1608728;1657738,1663997;1700457,1701038;1731194,1732000;1778037,1778896;1800001,1801352;1804001,1806380;1888360,1889054;1960900,1961074;1967432,1967852;1968001,1971110;2048118,2048909;2167254,2168000;2180590,2181602;2202400,2202824;2225033,2226042;2239730,2240000;2301525,2302046;2312098,2312296;2324457,2324953;2367057,2368000;2392013,2396845;2458287,2458921;2470379,2470816;2473751,2474171;2476529,2477296;2483881,2484418;2504001,2506131;2508807,2509631;2521634,2523425;2564912,2565179;2566033,2566401;2584001,2586086;2606863,2608000;2654138,2654586;2655905,2656653;2710508,2712000;2712009,2716466;2784690,2788000];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1075J %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1075J' - 2    - 7T   - 83F   - 150/600   - 0.2500   - 7T   - 34F   -   134/560 - 0.2393               - :)  - Done.
% 'R1075J' - 1/2  - 7T   - 83F   - 102/300   - 0.3400   - 7T   - 34F   -   99/297  - 0.3333               - :)  - 105 recall (3 words repeated)
% 'R1075J' - 2/2  - 7T   - 83F   - 48/300    - 0.1600   - 7T   - 34F   -   35/263  - 0.1326               - :)  - 48 recall

% First subject in which I'm scrolling until the end of recall trials too.

% Lots of high frequency (> 240 Hz) noise on half of the channels, especially surface. Squashed by lowpass filter.
% Re-referencing introduces weird side lobes on lines at harmonics. Using non-ref for peak detection.
% Additionally, left channels have the wide side lobes. Removing these. 
% Alternatively, could do an 'R*' and 'L*' specific re-ref.
% Saving L* channels goes from 7/34 to 7/79

% In 2 sessions, the second session has more apparent peaks at more frequencies. Combining both sessions captures all peaks.
% Peak detection on combined sessions.
% Relatively free of large interictal events, just slinky.
% Some occasional dips.
% Great accuracy and number of trials.
% Keeping 'RFB1', 'RFB3', 'RFB4' even though some slow drifts.
% Almost no buzz or IEDs.
% In Session 2, sharp buzz in ROF. Not sure if in Session 1. RPIH are dodgy too. Cannot remove ROF - these are the only temporal channels.
% Much more buzz in Session 2. Very slight. Hope I got them all.
% Had to remove a lot of buzz in ROF (temporal channels) of Session 2, but I left some in that seemed relatively small.
% All the same, baby with the bath water?

% Decent coverage for phase encoding.
% Again worrying for HFA.

% Channel Info:
info.R1075J.badchan.broken = {'LFB1', 'LFE4', ... % big fluctuations, LFE4 breaks in session 2
    'RFD1', 'LFD1', 'RFD8', 'LFC1', ... % sinusoidal noise + big fluctuations. Confirmed.
    'RFD2', 'RFD3', 'RFD4', ... % big drifts, almost look like eye channels. Confirmed.
    'L*', ... % bad line spectra (ringing side lobes)
    'RFA8' ... % buzzy. Confirmed.
    };


info.R1075J.badchan.epileptic = {}; % no Kahana channels

info.R1059J.refchan = {'all'}; % {'R*', 'L*'};

% Line Spectra Info:
% z-thresh 1
info.R1075J.FR1.bsfilt.peak      = [60  120 180 240 300];
info.R1075J.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5 0.5]; 
info.R1075J.FR1.bsfilt.edge      = 3.1840;

% keeping in L*
% info.R1075J.FR1.bsfilt.peak      = [60  120 178.7 180 181.4 220 238.7 240 280.1 300 ...
%     100.2 139.8 160.1 260];
% info.R1075J.FR1.bsfilt.halfbandw = [0.5 0.5 0.5   1.7 0.5   0.8 0.5   1.7 0.5   3.1 ...
%     0.5   0.5   0.5   0.5];
% info.R1075J.FR1.bsfilt.edge      = 3.1840;

% Bad Segment Info:
info.R1075J.FR1.session(1).badsegment = [499288,502539;1273396,1273957;2382362,2385083];
info.R1075J.FR1.session(2).badsegment = [313863,314505;366283,366530;398972,399239;579045,579485;753718,754695;756332,756744;848723,849348;856082,857276;886117,889453;947593,948546;1052670,1056000;1183440,1185784;1198605,1199924;1200001,1205268;1216751,1217228;1217811,1218231;1218807,1219078;1270504,1270965;1375581,1375916;1376001,1376776;1389037,1396498;1438275,1440990;1444444,1447449;1460001,1461026;1492654,1494215;1600001,1601030;1621811,1622864;1842267,1843715;1846654,1848000;1967335,1975114;2042500,2042634;2060178,2068000;2125839,2126513;2162766,2164000;2167464,2175775;2185872,2186372;2212134,2215150;2250351,2258497;2304106,2305695;2468352,2469526;2498194,2499521;2528098,2528635;2606254,2607892;2608001,2610461;2625331,2625671;2667359,2667868;2729118,2730006;2741428,2746195];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1080E %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1080E' - 2    - 6T   - 10F   - 107/384   - 0.2786   - 6T   - 7F    -    106/377  - 0.2812                - :)  - Good pending clean. ***
% 'R1080E' - 1/2  - 6T   - 10F   - 47/180    - 0.2611   - 6T   - 7F    -   47/176 - 0.2670                   - :)  - 47
% 'R1080E' - 2/2  - 6T   - 10F   - 60/204    - 0.2941   - 6T   - 7F    -   59/201 - 0.2935                   - :)  - 59

% Lots of reference noise, but for surface channels, it goes away after re-referencing.
% A couple borderline slinky channels, but relatively low amplitude (RPTS7, RSFS2). Will keep them in. 
% Weird number naming conventions in surface channels.
% Re-referencing fixes very bad baseline of line spectra. 
% Doing line detection on individual re-ref sessions. 
% Noise consistent on channels.
% Low amplitude slink in remaining channels, no events.
% Buzz remains, use depth channels to detect strong buzz events.
% RPTS7 (high amplitude slink).
% Removing a lot of buzz episodes. Some mild ones (where I can barely tell they're there, except for the depths) might be left in.
% Seems like most of the buzz episodes are when the subject is on a break. 

% Again, buzz is worrying.
% Low channel number, but good data for phase encoding.

% Channel Info:
info.R1080E.badchan.broken = {'L9D7', 'R12D7', 'R10D1', ... sinusoidal noise, session 1
    'RLFS7', 'RLFS4', 'RSFS4', ... % sharp oscillations/buzz. RLFS4 on Session 2. Confirmed.
    'L5D10', 'R10D7', ... sinsusoidal noise, session 2
    };

info.R1080E.badchan.epileptic = { ...
    'R6D1', 'R4D1', 'R4D2', 'L1D8', 'L1D9', 'L1D10', 'L3D8', 'L3D9', 'L3D10', 'L7D7', 'L7D9'}; % Kahana

info.R1080E.refchan = {'all'};

% Line Spectra Info:
info.R1080E.FR1.bsfilt.peak      = [59.9 179.8 239.7 299.7]; % 239.7 is apparent in session 2, but not 1
info.R1080E.FR1.bsfilt.halfbandw = [0.5  0.5   0.5   0.6];
info.R1080E.FR1.bsfilt.edge      = 3.1852;

% Bad Segment Info:
info.R1080E.FR1.session(1).badsegment = [412427,416452;430126,432416;560790,560980;568339,572606;608428,611388;874141,875004;877988,878751;879193,882295;957043,957410;994263,997785;1069144,1070928;1098078,1100618;1243373,1246052;1336276,1337328;1342657,1344128;1360034,1361449;1387330,1389651;1408880,1411963;1513731,1517627;1606550,1606688;1657378,1657753;1658631,1661379;1679513,1680847;1684194,1686813;1693241,1695699;1699884,1704525;1793491,1796119;1914617,1917392;1926182,1929433;1962565,1965928;2052180,2056362;2057941,2060624;2084958,2085615;2086553,2088616;2134940,2137003;2138155,2140355;2247485,2251284;2368448,2371108;2378044,2381616;2429081,2431648];
info.R1080E.FR1.session(2).badsegment = [280893,282336;309485,311688;488910,490095;504653,507159;581350,582833;715378,717433;832450,836519;861195,863448;943822,947658;1039513,1042345;1153382,1155212;1272827,1274463;1373384,1374544;1374625,1376990;1537904,1540359;1646776,1647768;1691851,1692956;1693342,1694854;1927692,1929304];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1120E %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: 
% FINISHED FINISHED

% 'R1120E' - 2    - 14T  - 4F    - 207/600   - 0.3450   - 8T  - 4F    -                      - :)  - Good pending clean. Not the cleanest.
% 'R1120E' - 1/2  - 14T  - 4F    - 97/300    - 0.3233   - 8T  - 4F    -     97/300    - 0.3233-                 - :)  - 97
% 'R1120E' - 2/2  - 14T  - 4F    - 110/300   - 0.3667   - 8T  - 4F    -    110/299 - 0.3679                  - :)  - 112

% When switching to channel labels using individual atlases, channel numbers go to 14T and 4F (vs. 12T and 1F)
% Very clean line spectra.
% Remaining channels very slinky. Not a particularly clean subject.
% Cleaning individual re-ref sessions, baseline too wavy on combined. Same peaks on both sessions. 
% Lots of slinky episodes, some large amplitude episodes.
% Perhaps some ambiguous IED episodes in surfaces. Keeping them in mostly.
% Ambiguous buzz. Mostly leaving them in.
% LPOSTS10 has oscillation with spike atop. Not a T or F channel.
% LANTS5-8 are a little dodgy (spiky). Could take out.

% Not super for either HFA (buzz) or phase encoding (coverage, IEDs). 

% Channel Info:
info.R1120E.badchan.broken = {
    };
info.R1120E.badchan.epileptic = {'RAMYD1', 'RAMYD2', 'RAMYD3', 'RAMYD4', 'RAMYD5', 'RAHD1', 'RAHD2', 'RAHD3', 'RAHD4', 'RMHD1', 'RMHD2', 'RMHD3' ... % Kahana
    'LPOSTS1', ... % spiky. Confirmed.
    'LANTS10', 'LANTS2', 'LANTS3', 'LANTS4' ... % big fluctuations with one another
    'LANTS5', 'LANTS6', 'LANTS7', 'LANTS8'}; % spikes, especially Session 2

info.R1120E.refchan = {'all'};

% Line Spectra Info:
% session 2 z-thresh 1 + 2 manual
info.R1120E.FR1.bsfilt.peak      = [60  179.8 299.7 ...
    119.9 239.8]; % manual
info.R1120E.FR1.bsfilt.halfbandw = [0.5 0.5   1 ...
    0.5   0.5]; % manual
info.R1120E.FR1.bsfilt.edge      = 3.1852;

% Bad Segment Info:
info.R1120E.FR1.session(1).badsegment = [170475,171499;177831,179269;353469,354723;387613,388601;979690,980806];
info.R1120E.FR1.session(2).badsegment = [334134,334682;432274,434280;438585,439560;1164557,1164646;1380526,1381908;2021263,2021976;2318696,2321676;2327103,2329025];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1128E %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1128E' - 1    - 8T   - 10F   - 141/300   - 0.4700   - 4T - 9F    - 134/278   - 0.4820   - :) - Done. Core. 26. 147 recall. 

% Mostly depth electrodes. Very frequency epileptic events that are present
% in temporal grids.
% Ambiguous IEDs, not sure if I got them all OR if I was too aggressive. 

% Not great for phase encoding.

% Channel Info:
info.R1128E.badchan.broken = {'RTRIGD10', 'RPHCD9', ... % one is all line noise, the other large deviations
    };
info.R1128E.badchan.epileptic = {'RANTTS1', 'RANTTS2', 'RANTTS3', 'RANTTS4', ... % synchronous swoops with spikes on top
    'RINFFS1'}; % marked as bad by Kahana Lab
info.R1128E.refchan = {'all'};

% Line Spectra Info:
info.R1128E.FR1.bsfilt.peak      = [60  179.9 239.8 299.7];
info.R1128E.FR1.bsfilt.halfbandw = [0.5 0.5   0.5   0.7];
info.R1128E.FR1.bsfilt.edge      = 3.1852;

% Bad Segment Info:
info.R1128E.FR1.session(1).badsegment = [240728,241107;278500,278928;339661,340117;366194,366654;377155,377797;457180,457435;462388,462852;472334,473000;487250,487512;751091,751673;778825,779287;811298,811903;851544,852080;856877,857482;945783,947052;1056745,1057354;1059291,1060215;1062937,1063458;1067803,1068927;1081370,1081596;1088020,1089028;1122046,1122559;1211260,1212163;1280042,1280526;1306023,1306692;1571722,1572790;1638470,1638894;1703062,1703764;1710123,1710551;1815353,1816167;1816803,1817247;1819425,1819849;1911358,1911874;1939914,1940656;2038859,2039464;2133429,2133864;2323550,2324143;2331405,2331849;2333257,2333664;2338720,2339212;2341287,2342142;2384541,2384808;2675600,2676282;2676897,2677320;2906172,2906769];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1135E %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1135E' - 4    - 6T   - 14F   - 107/1200  - 0.0892 - 6T - 14F - 38/503  -0.0755                                  - !!! - Performance.
% 'R1135E' - 1/4  - 6T   - 14F   - 26/300    - 0.0867 - 6T - 14F - 18/199   - 0.0905                   - !!! - 
% 'R1135E' - 2/4  - 6T   - 14F   - 43/300    - 0.1433 - 6T - 14F - 6/38 - 0.1579                                    - !!! - 
% 'R1135E' - 3/4  - 6T   - 14F   - 26/300    - 0.0867 - 6T - 14F - 7/112 - 0.0625                                    - !!! - 
% 'R1135E' - 4/4  - 6T   - 14F   - 12/300    - 0.0400 - 6T - 14F - 7/154 - 0.0455                                    - !!! -

% Frequent interictal events, and lots of channels show bursts of 20Hz activity. 
% RSUPPS grid goes bad in Session 3. 
% Session 3 has lots of reference noise. 
% FR1 was done prior to a re-implant. Localization folder 0 is the same in both releases. This one is presumably the pre-re-implant.
% Line detect on individual re-ref; combo makes wavy baseline.
% An amazing amount of IEDs in RANTTS1-3-5, RPOSTS3. Removal of these would lead to only 2T. Likely to lose more than half of trials.
% Ambiguous IEDs remain.

% Channel Info:
info.R1135E.badchan.broken = {'RAHCD3', ... Kahana broken
    'RROI1*', 'RROI2*', 'RROI3*', 'RROI4*',  ... Kahana brain lesion
    'LHCD9', 'RPHCD1', 'RPHCD9', 'RSUPPS*' ... mine, 
    };

info.R1135E.badchan.epileptic = {'RLATPS1' ... % periodic bursts of middling frequency
    'LROI3D7', 'LIPOS3' ... Kahana epileptic
%     'RANTTS3', 'RANTTS5', 'RLATPS3', 'RPOSTS3' % IEDs
    };

info.R1135E.refchan = {'all'};

% Line Spectra Info:
% Re-referncing prior to peak detection.
info.R1135E.FR1.bsfilt.peak      = [60  119.9 179.8 239.7 299.7];
info.R1135E.FR1.bsfilt.halfbandw = [0.5 0.5   0.5   0.5   0.5];
info.R1135E.FR1.bsfilt.edge      = 3.1852;

% Bad Segment Info:
info.R1135E.FR1.session(1).badsegment = [187396,188428;193094,193759;198141,198730;201098,201429;205339,205743;207313,207975;210483,211112;243317,243756;260079,260829;278262,279036;284176,285027;288478,289148;292365,292954;295076,295704;301264,301824;313014,313853;316788,317361;320148,320830;322718,323576;355072,355496;360954,363636;364269,364963;391318,394095;398497,399371;400789,401628;406319,407335;409852,410530;411387,413000;415516,416259;449313,450027;451549,452879;457631,458192;460197,460798;461414,463167;463537,466560;466582,473213;477579,479110;489361,489906;498280,499143;502006,503496;509309,510063;515920,516747;552154,552747;554461,555444;568464,569983;571699,572215;582530,583925;587663,588344;601564,602314;603687,604236;609008,609673;611973,612812;613274,613859;615050,615918;644408,646833;649995,650942;651788,652478;653516,654954;661798,662564;674212,674938;691103,691705;700719,701360;706273,706939;708187,708844;757516,758178;760276,760974;762241,762830;764135,764873;765698,766452;786640,787212;802266,803196;806415,807192;809001,809743;811189,815184;818910,819180;820639,823020;824135,824861;828071,829804;852917,853780;854987,855529;867133,867702;883963,884588;887113,889812;891109,895104;897066,897812;900430,901249;903097,904544;907653,912717;915552,916238;918319,920761;924430,924947;942106,943056;971512,972174;974287,975024;978509,979020;991009,991670;992874,993567;1013144,1013688;1014985,1016162;1018134,1018980;1021361,1021966;1022977,1024327;1025792,1026972;1031899,1032835;1057285,1057793;1059823,1060452;1065019,1065689;1069200,1070055;1078646,1079711;1090207,1090908;1098082,1098900;1105233,1106023;1113479,1114196;1115835,1116573;1118881,1119591;1128858,1130466;1161487,1162237;1164577,1166832;1170325,1170828;1173181,1173850;1175989,1176530;1179099,1179696;1183224,1185041;1200255,1201673;1207715,1208373;1269037,1269605;1271406,1271938;1274221,1274724;1278068,1278516;1284026,1284627;1286261,1286712;1292219,1292510;1295957,1296659;1303925,1305610;1311696,1312901;1313963,1314684;1318778,1319290;1320683,1321920;1323176,1323910;1359334,1360684;1370080,1371141;1374113,1375903;1381573,1382331;1392176,1392873];
info.R1135E.FR1.session(2).badsegment = [156878,158222;161027,163309;166004,169002;175825,179008;181088,182865;184045,185896;187972,189568;190090,190748;191625,192857;208451,209763;213599,215010;217956,219020;222568,223776;225444,229026;231542,235764;238020,244582;247753,249991;254016,258120;260170,261121;263303,263736;265136,266448;266798,267238;274474,275405;278206,279960;283717,284469;286168,297095;325147,325698;328511,330141;330989,331668;334651,339660;340692,341311;342075,356524;361667,363636;378456,379620;386619,387948;390347,391608;392664,395604;398678,399600;400561,401541;422432,423045;433047,435564;440207,441276;444119,447552;452749,454800;456407,457650;459541,463536;468067,471528;480302,487512;489515,491271;494356,495993;498390,499020;500306,503496;507493,510375;530437,531468;538240,542889;545028,549254;553382,554700;556689,557919;561350,562100;563965,566994;575425,576227;581427,582326;583417,584505;589056,589581;590683,591408;592162,594414;600404,602080;605403,606141;608017,609782;609842,610696;612847,613804;640775,641706;647772,648993;651231,654966;656573,658536;660199,661980;663981,664888;668094,670499;671329,673017;674225,676317;682180,682930;685931,687312;688187,691308;693379,694634;695305,697948;700296,707076;708251,710983;712525,713855;718052,719280;753899,755244;759841,760462;761456,763236;764461,765562;767893,771228;774910,778581;779221,780487;782781,783641;787608,791208;794008,795204;799201,799762;801134,802706;803853,805022;811813,813127;815576,816253;818950,820471;821972,823064;827769,828362;847979,848769;856651,858783;860345,860990;865501,866932;868389,869808;871129,872701;874190,875124;878701,879440;880583,882513;887326,888628;889634,890219;892688,894050;896442,899100;901127,901784;903745,910010;914327,915084;917236,919080;921948,923076;925570,927072;959480,960033;964386,965011;966388,966807;970500,972005;974275,976113;981804,982477;987323,990622;991009,991864;995005,996118;1001433,1001962;1011428,1013982;1015694,1017201;1018328,1018980;1021148,1022441;1025885,1026550;1027589,1029717;1032685,1034083;1036270,1036996;1039247,1040053;1042179,1042956;1072685,1073318;1078731,1079305;1081974,1082916;1085869,1087268;1090674,1094470;1094905,1096352;1098485,1098900;1101317,1102896;1107489,1110888;1113474,1114884;1119995,1122876;1124991,1126265;1127747,1130313;1132399,1134309;1140057,1148247;1186813,1189122;1190809,1197689;1198801,1201778;1203244,1205752;1207337,1209786;1210789,1212739;1226349,1226772;1235570,1237609;1238761,1240151;1242757,1245786;1248098,1248816;1251840,1254137;1256179,1258141;1260320,1262736;1276569,1277759;1278721,1279419;1297588,1301916;1302611,1303270;1305568,1310688;1311615,1314684;1317210,1317723;1318681,1319334;1394605,1395250;1399020,1400150;1401241,1402596;1405549,1406090;1436961,1438170;1444901,1446552;1448877,1449844;1451822,1453103;1455959,1457103;1461521,1462536;1465247,1466046;1469497,1470528;1472327,1472912;1476547,1477260;1478521,1480024;1481630,1482516;1484567,1486512;1487661,1489313;1490509,1491416;1493811,1494504;1498501,1501353;1504446,1506492;1506896,1512761;1528632,1529398;1544064,1545551;1546453,1549817;1552902,1554444;1555766,1557136;1558441,1559638;1562860,1569338;1570836,1571376;1576837,1577970;1586413,1588524;1589784,1590408;1591525,1593503;1594643,1595381;1596543,1598188;1599627,1600790;1606393,1609302;1611082,1615441;1623497,1624029;1650550,1651103;1657148,1658273;1659984,1661413;1664222,1665439;1666123,1666660;1667412,1668489;1672395,1675248;1676778,1678320;1682941,1683653;1684971,1685653;1689257,1690308;1692613,1694304;1696037,1698300;1699767,1700491;1702297,1703542;1707392,1708471;1711860,1714284;1719920,1720930;1723767,1724658;1740194,1741266;1754245,1757234;1758829,1760070;1762237,1766232;1767715,1771744;1775369,1776000;1777133,1777504;1786982,1788552;1789727,1790838;1792569,1794204;1794906,1795456;1796458,1797619;1799325,1801100;1802777,1805110;1806568,1808246;1810055,1811636;1812585,1820665;1822177,1823763;1824950,1826172;1830668,1832031;1852187,1854144;1855776,1857181;1858459,1862136;1873053,1875519;1877113,1879513;1886620,1888718;1891055,1892468;1895442,1895878;1897327,1902096;1903229,1903872;1907503,1910088;1912747,1917356;1918081,1920829;1922077,1925715;1957327,1958040;1963513,1964356;1967052,1967655;1968693,1970028;1974025,1978020;1989553,1990244;1992357,1993234;1994710,1995470;1996854,1998000;2001997,2002528;2010895,2012126;2013985,2016906;2021098,2021976;2023532,2024636;2044621,2045952;2051375,2052064;2059959,2060610;2066795,2067881;2079435,2081027;2083701,2085104;2087637,2088479;2093905,2095682;2105507,2107320;2109288,2112395;2113885,2115855;2126815,2129005;2145853,2147463;2157841,2158666;2183672,2184935;2185813,2186456;2189809,2193056;2194228,2197800;2213361,2214082;2215482,2216819;2225773,2229768;2230921,2233764;2235642,2237038;2238844,2239576;2257858,2260418;2277721,2278374;2280822,2281716;2283090,2285712;2287892,2288952;2290458,2293704;2294587,2295256;2297007,2297700;2300564,2302741;2305693,2309688;2320361,2321676;2322543,2324123;2332718,2333664;2335779,2337023;2338718,2339839;2346632,2348789;2352778,2353644;2355554,2356769;2359558,2360175;2361774,2362256;2377270,2378262;2380376,2381212;2394809,2395698;2400376,2400973;2404134,2405233;2408416,2409588;2411139,2413584;2414338,2417184;2419148,2420256;2428428,2429945;2432098,2435241;2436718,2437560;2442391,2446454;2453012,2454243;2456775,2457540;2506178,2507032;2509916,2510275;2516679,2519351;2521477,2524225;2541457,2544352;2547422,2549448;2553445,2556559;2557920,2558630;2563402,2565133;2568161,2569428;2581755,2582399;2602893,2604930;2608281,2608974;2612264,2614135;2617381,2619746;2622239,2625372;2626517,2627468;2629239,2630778;2634464,2637360;2641663,2648523;2649365,2649934;2653247,2655889;2659371,2661336;2662759,2664787;2665512,2668940;2669581,2671217;2674126,2677320;2700265,2700999;2703125,2704564;2707001,2709288;2722646,2727195;2730501,2732564;2736289,2737046;2741873,2743008;2744292,2745252;2746161,2747785;2748563,2748959;2749249,2750539;2761978,2762664;2764668,2765232;2769229,2773224;2775903,2777220;2787464,2788049;2804620,2805192;2808604,2809188];
info.R1135E.FR1.session(3).badsegment = [243757,244696;253312,253913;256087,259740;260877,263736;266572,269248;271245,273285;277034,278497;308225,308689;311060,316995;318029,319680;320970,321543;328829,329452;331219,331668;336744,337349;338637,339158;340732,342247;347028,347652;349046,350920;353667,355037;359282,360971;363024,365003;365933,367375;372000,372528;402972,403596;405107,405749;415157,416025;419391,423576;427383,429048;442449,442925;445325,447552;448805,451388;454006,454546;457933,459279;460536,461052;474847,475412;478940,479400;511303,512755;515013,515484;515960,518426;519787,520304;522236,522829;523477,525629;527473,528138;530501,532042;533624,539460;556061,556541;564186,564767;566973,567344;573366,575115;576496,579420;581185,582571;583868,586233;595534,595978;611687,612675;617080,618608;620770,622338;623957,624852;627788,628965;650301,650878;651905,654161;657761,660542;672851,673299;689882,690415;706019,707292;708686,710290;711071,712071;713593,716692;733995,734548;744276,746371;753750,754854;755245,756418;757677,759240;774012,776559;777653,778524;796606,797683;800828,801353;824732,826682;836333,838585;845444,845937;850218,850766;853819,854287;859942,860495;866790,867132;874061,874537;875661,876294;882061,882360;883117,885691;916599,916910;917960,919080;923294,923859;925155,926751;929485,930135;937828,939396;942770,943056;944881,945499;956438,958566;961739,962771;965361,966139;967255,968343;971029,971461;982029,982526;985965,988222;989433,990542;1026973,1027522;1029047,1029636;1032012,1033060;1038961,1039635;1043448,1047711;1057023,1058550;1060649,1061322;1066473,1067047;1068415,1069145;1082320,1087413;1089901,1091647;1122877,1123998;1127791,1129319;1131650,1133057;1135292,1135728;1138457,1138860;1145148,1145774;1149724,1150848;1151441,1152707;1154031,1154519;1222639,1223116;1424868,1425357;1444446,1444874;1446117,1446552;1450549,1451198;1468237,1468777;1483451,1483911;1486371,1486824;1490815,1492197;1493211,1494504;1496684,1497969;1543701,1544282;1545779,1546292;1546876,1547517;1548253,1548846;1550359,1552053;1554932,1556141;1558441,1559308;1583424,1584009;1593240,1593765;1594405,1594817;1595649,1596069;1597297,1597886;1601905,1602396;1606627,1607058;1609426,1610002;1615186,1617237;1641506,1642356;1649414,1650075;1651054,1656154;1665188,1665681;1710289,1710942;1713064,1713616;1726099,1726934;1727521,1728296;1738575,1741403;1742257,1747466;1750913,1757077;1772637,1773444;1780436,1781226;1785705,1786212;1787127,1789359;1791341,1793371;1794205,1798200;1798656,1800546;1801813,1804856;1806415,1807084;1848581,1850148;1855981,1858069;1860211,1861920;1862987,1864796;1865685,1867290;1882596,1883673;1892554,1893122;1894363,1895669;1944546,1945235;1954045,1955669;1967205,1967721;1983205,1983778;2055109,2055762;2064486,2065932;2069521,2069928;2070714,2072141;2074710,2075336;2087468,2088415;2092797,2093390;2094155,2094663;2100970,2101494;2102960,2103904;2106900,2109317;2110924,2111432;2112785,2113884;2116104,2117880;2122731,2123235;2146292,2147340;2154373,2154772;2155496,2157785;2158409,2158817;2160020,2160633;2162397,2164693;2166594,2168335;2186272,2187058;2192886,2193290;2196616,2197406;2210961,2212742;2215633,2220665;2243388,2243884;2246309,2248219;2256238,2257740;2260999,2261697;2263203,2265242;2285713,2288150;2290877,2291454;2294591,2295168;2301697,2305692;2309535,2311245;2314716,2318121;2365350,2366045;2369629,2370117;2399240,2400006;2402978,2403499;2405137,2405592;2406793,2407265;2408976,2409588;2411727,2412288;2413585,2414150;2415796,2418734;2424013,2424985;2451253,2452591;2456002,2457239;2457541,2458150;2459486,2461536;2467965,2468542;2469419,2470033;2471772,2473524;2476493,2479447;2507946,2508937;2510319,2510908;2513174,2513484;2514758,2515286;2529469,2530328;2562162,2562711;2563962,2564507;2567141,2568434;2579064,2579790;2580723,2581416;2583237,2584016;2602984,2605392;2608067,2609388;2611624,2612116;2618577,2619613;2623556,2624427;2629369,2630441;2653247,2653773;2671826,2672455;2679721,2680346;2682199,2682780;2692563,2693011;2699621,2700963;2703882,2704798;2706147,2706981;2707701,2708572;2716982,2717564;2722441,2724041;2726046,2726885;2728257,2728834;2750804,2751227;2759581,2760061;2763875,2765232;2771537,2772963;2776926,2778374;2779786,2781116;2789209,2789641;2806864,2807502;2808709,2810297;2811903,2813184;2815138,2815655;2816725,2817180;2819090,2820339;2859312,2859872;2863529,2864561;2866458,2867317;2889745,2890326;2905238,2905750;2913721,2914165;2915803,2916364;2918466,2918761;2920291,2921493;2924303,2925751;2927147,2927647;2963562,2964719;2989988,2990846;2995244,2995849;3008662,3009393;3010958,3011463;3011977,3012984;3013565,3013892;3023208,3023656;3032965,3033494;3047490,3048087;3061138,3061876;3065058,3068132];
info.R1135E.FR1.session(4).badsegment = [149786,150488;157275,159084;161162,162891;163711,164092;203341,203796;206737,207792;209106,209453;241058,241844;249082,249824;254173,255415;263737,264117;265316,265961;276273,276854;278681,279463;280309,280866;310480,310880;333473,334602;344684,350960;367951,369253;370545,371259;372632,374312;381892,382469;387613,389539;408729,409245;422662,423239;427573,429608;431057,433370;434952,437837;442175,442852;445583,450099;477313,477850;479521,486357;489889,491130;517374,529033;537825,544553;551993,552453;556770,557411;558627,559095;560383,561029;563114,566128;568565,570430;580335,582100;619405,620123;623050,623942;627828,629235;631663,632320;638808,639360;660706,663336;664300,664836;725335,726278;731704,732200;736095,737960;739386,739979;745617,746194;747994,748925;767233,767705;770394,770915;780711,781892;828760,830174;836152,838279;840345,841027;843366,847152;868986,869885;918762,919080;919596,921096;987710,988234;991190,992383;1039690,1040601;1044093,1046952;1051412,1056557;1061168,1062936;1069808,1070486;1073470,1074091;1077104,1078920;1080894,1081930;1086469,1087466;1095010,1095599;1100145,1102896;1102994,1104046;1105760,1106892;1107457,1108034;1142917,1144835;1148907,1149307;1151046,1152284;1155199,1155825;1157716,1161919;1163195,1163764;1165511,1166832;1168134,1169850;1183864,1184441;1196009,1196554;1198051,1198559;1211832,1212759;1250079,1250748;1251530,1253956;1259840,1262736;1266846,1267511;1285580,1286202;1286615,1287121;1288191,1290383;1293145,1293847;1295994,1297956;1343410,1344204;1347591,1348273;1349122,1349735;1351950,1352841;1354794,1355460;1374149,1376285;1378201,1378620;1400631,1401083;1404224,1405341;1414786,1415246;1418193,1418799;1419821,1424926;1427556,1428116;1448361,1449570;1450549,1452620;1454214,1456185;1459230,1460246;1469082,1469659;1470827,1471847;1474996,1476858;1489799,1490288;1492680,1493466;1495270,1496431;1503709,1505051;1507911,1508387;1511335,1514179;1519572,1520902;1554090,1555574;1558578,1559586;1562691,1564762;1567444,1569797;1570542,1571231;1590409,1592971;1604926,1608790;1612056,1612661;1617289,1617898;1618570,1619292;1655654,1657076;1667275,1668690;1681708,1682316;1719803,1720280;1754245,1755349;1762006,1764598;1776907,1777569;1778547,1779672;1791457,1791942;1792935,1793698;1804835,1805400;1819433,1820175;1821149,1821794;1822177,1822710;1849637,1851000;1858435,1859121;1860722,1861420;1862137,1863117;1866657,1868212;1882653,1883137;1901053,1901634;1902931,1903576;1904912,1906092;1907905,1909461;1911974,1912567;1916819,1917372;1918935,1919492;1925867,1926304;1948361,1949316;1962242,1962856;1989126,1991174;2002951,2003657;2005291,2007573;2020212,2020809;2026855,2027375;2047661,2049208;2050746,2051146;2053945,2055843;2060583,2061442;2078396,2078852;2088261,2089144;2090642,2092894;2093654,2094144;2099387,2099920;2104172,2104922;2106856,2107267;2110533,2111843;2117175,2117700;2119335,2119944;2142070,2143255;2144209,2144810;2153845,2154998;2157723,2159380;2160958,2161535;2162920,2164995;2165833,2166418;2168745,2169414;2172773,2173334;2203070,2203779;2205164,2206096;2221321,2222036;2260411,2261048;2262977,2264613;2269789,2270789;2278982,2279583;2303860,2311273;2312154,2312924;2314821,2315369;2320669,2321323;2322124,2322689;2326648,2329166;2361951,2362814;2370032,2372546;2373625,2380719;2382394,2382842;2395453,2395881;2396992,2397600;2402253,2404099;2413871,2414532;2420030,2420594;2422088,2422738;2424465,2424937;2468654,2471370;2473887,2474392;2481960,2483282;2495986,2496776;2508127,2508744;2518162,2521937;2523974,2524800;2526230,2526743;2547060,2547532;2555817,2556342;2564679,2566936;2573614,2574207;2577421,2578666;2581590,2584918;2586698,2587846;2612788,2614292;2615471,2616813];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1142N %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1142N' - 1    - 18T  - 59F   - 48**/300  - 0.1600   - 17T  - 56F   - 38**/200  - 0.1900   - ??? - Done. Expansion. 50 recall. 

% 'AST1', 'AST2', 'PST1', 'PST2' buzzy channels, though Roemer says they're ok
% Lots of slow swoops, and I'm not sure how I feel about them.
% Removing swoops if they are preceded by spikes and are in both ALF/AALF and MLF/PLF
% Lots of these swoopy IEDS
% IEDs are very widespead, unlikely I can narrow down where they are from

% Good for HFA.
% Would be great coverage for phase encoding, but swoops are annoying.

% Channel Info:
info.R1142N.badchan.broken = {'ALT6'}; % flat line

info.R1142N.badchan.epileptic = {'PD1', 'PD2', 'PD3', 'AD1', 'AD2', 'AALF1', 'AALF2', 'MLF2', ... % Kahana
    }; 
info.R1142N.refchan = {'all'};

% Line Spectra Info:
% Session 1/1 eyeballing
info.R1142N.FR1.bsfilt.peak      = [60  120 180 240 300];
info.R1142N.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5 0.5];

% Bad Segment Info:
info.R1142N.FR1.session(1).badsegment = [1,1915;2978,3154;6479,7036;7459,7503;15373,15544;16498,17176;20396,21061;23583,23995;25506,26211;29605,30170;32562,33144;33417,33998;35838,35877;36151,36762;38320,39641;44001,44776;45968,46098;46986,47041;48001,48703;50210,50275;50938,51401;53054,53566;54376,55014;57495,58176;58629,59114;60122,60381;61903,62630;63349,64137;64458,64502;66374,66437;74591,75168;81675,81722;82156,82219;82250,82281;82629,82665;83172,83235;83855,83904;83981,84016;84605,84631;85033,85066;86548,86638;87802,88711;88955,88996;89516,89558;91976,92004;92535,92596;92828,92889;103419,104000;104186,104227;104802,104840;105183,105254;105339,105450;105530,105558;109885,110514;112261,112287;112640,112674;112707,112746;115328,115439;118556,118582;119072,119103;120933,121587;122605,122630;122750,122778;122882,122998;123336,123369;125143,125187;130180,130213;130608,130649;130718,130759;133465,133499;133605,134281;134565,134622;135349,135399;136001,137079;137404,137439;137793,137883;139906,139950;142218,142867;159712,159772;160001,160749;161562,162047;162280,162342;162403,162482;162661,162781;162852,162896;163223,163920;165025,165544;165559,165611;167782,168518;169425,170047;170680,171718;172001,173184;173793,174953;175508,177219;177734,178058;180001,197372;198927,200000;202540,215995;216001,232000;233000,236000;240525,240905;241557,241888;242731,243254;244001,244321;244323,249982;252057,252101;253428,253482;254680,254719;255140,255176;255717,255864;256135,256988;258586,259853;261782,262713;264624,265246;266651,266695;268850,269370;270046,270084;270532,270969;272275,272692;273331,273372;278573,278619;280267,280754;284001,284504;285484,285512;286180,286222;287099,287143;287309,287393;288780,288819;291787,291837;297928,298587;312952,313840;314470,314850;315615,315659;316226,317047;318137,318313;318978,319643;320052,320719;321559,321601;333694,333719;334199,334375;334438,334471;334890,334928;335551,336000;336323,336800;345495,346168;347148,347705;372092,372735;376001,376574;377551,377571;380001,380980;383083,383122;384170,384803;386796,386834;389839,390434;392619,393577;398532,400000;418532,419073;420001,420571;432952,433509;433573,433603;437917,438547;439314,440000;442667,443383;450556,451079;457831,458283;459699,460287;468001,469512;478309,479374;480001,480641;481430,482380;485140,486160;490922,491538;510836,511458;514100,514160;515301,516000;518866,520000;522264,523667;525648,525711;530968,531452;536885,537644;541895,542297;545879,546488;576901,577574;587341,587377;602935,602966;616140,616768;632001,632663;648718,649241;652363,652545;659137,659826;669398,669896;670556,670939;674796,675213;705288,705802;707771,708000;709054,709547;712001,712383;712705,712760;734497,734912;737390,738101;742341,743087;747091,747692;748291,749104;761995,762727;789191,789792;822952,824000;832001,832582;834393,835606;836401,837015;838387,838936;855519,855987;857745,858222;858857,859423;892130,892905;901189,901945;915527,916000;918067,918600;920896,920964;929146,929633;932221,932800;934414,935108;948726,949241;968511,969149;972949,973364;1000474,1000966;1002382,1002842;1005796,1007049;1017019,1018246;1025008,1025910;1032879,1033534;1035505,1035915;1037519,1039211;1048425,1049023;1053245,1054076;1057522,1057998;1060154,1060214;1065968,1066633;1071134,1071557;1072487,1073265;1077911,1078469;1091188,1091305;1101893,1102466;1127602,1128000;1130195,1130698;1131678,1132310;1133393,1134032;1136342,1136860;1137068,1137754;1143616,1144780;1153202,1153829;1159075,1159761;1167376,1168000;1175513,1176000;1193116,1193813;1230852,1231630;1248272,1248840;1254274,1255197;1266855,1267721;1286624,1287151;1294847,1296000;1313070,1313783;1332001,1332510;1376581,1377343;1380054,1380596;1393847,1394504;1397162,1397877;1410396,1411138;1429003,1429617;1441113,1441708;1477549,1478630;1509035,1509544;1514003,1514547;1527468,1528000;1535659,1536257;1547263,1547737;1549368,1550114;1576001,1576590;1584001,1584913;1588699,1589302;1592646,1593421;1595355,1596101;1598823,1599731;1604296,1604800;1614307,1614832;1622113,1622784;1629960,1630590;1642312,1642721;1707301,1707864;1712888,1713659;1716159,1716692;1745884,1746582;1749819,1750679;1771218,1771619;1819505,1820000;1835255,1836000;1855266,1856000;1860885,1861558;1863653,1864000;1865988,1866888;1880269,1880864;1891834,1892628;1901237,1901848;1925988,1927586;1961106,1962788;1964659,1965235;1975700,1976268;1981775,1982546;1985301,1985802;2027149,2027937;2031864,2032640;2066791,2068485;2095193,2095979;2099331,2100579;2108052,2108437;2116848,2119009;2121581,2122449;2144724,2145184;2179069,2179767;2192001,2192812;2236461,2237292;2252449,2253052;2255307,2256389;2262427,2263036;2264001,2264667;2266226,2266824;2306785,2307404;2312398,2312907;2336987,2337515;2344311,2345026;2351296,2352518;2355654,2356188;2371766,2372433;2385009,2386413;2387567,2388000;2406914,2407356;2429782,2430345;2432759,2433469;2443825,2444716;2449178,2449759;2450237,2450885;2456001,2456808;2527072,2527571;2554710,2555533;2557702,2564000;2568001,2568708;2584066,2586239;2606444,2607006;2620573,2621141;2669646,2671187;2673086,2673727;2676251,2676932;2724001,2724448;2752995,2753566;2754621,2755149;2772001,2772848;2785809,2787033;2793807,2794369;2816569,2820000;2852324,2852941;2873785,2874380;2932291,2932867;2946527,2949077;2955790,2956611;2966100,2967340;2972001,2972657;2981253,2981843;2985116,2985902;3000304,3000843;3005503,3006144;3018073,3018872;3020748,3021310;3035046,3037259;3047132,3047767;3056001,3056499;3060001,3061052;3068490,3069036;3107661,3109211;3196589,3196918;3197328,3197835;3204001,3204674;3221121,3221687;3233718,3234380;3239207,3240000;3254208,3261587;3280576,3281101;3288505,3289240;3300850,3301507;3313033,3313776;3355807,3356511;3364271,3365042;3365404,3366110;3408904,3409719;3435929,3436469;3456001,3456598;3468670,3469417;3471367,3472000;3474538,3475181;3478738,3479312;3497589,3498856;3547295,3548000;3600719,3601631;3619841,3620191;3621440,3622268;3671296,3671780;3673605,3682800;3686745,3687240;3688643,3689101;3696001,3696434;3705561,3706610;3754239,3755364;3764057,3764706;3765127,3765730;3767244,3767791;3769654,3770763;3784190,3785002;3793215,3793757;3812815,3813643;3828108,3828633;3861283,3861942;3894694,3895388;3911081,3911767;3965315,3965981;4004296,4004948;4013213,4013797;4021011,4021746;4024997,4025796;4026787,4027469;4034831,4035457;4036614,4038679;4062667,4063254;4118368,4118842;4121597,4122149;4123340,4124357;4174954,4175466;4176651,4177257;4200070,4201054;4209129,4209679;4212440,4213082;4227745,4228411;4234680,4235245];
% info.R1142N.FR1.session(1).badsegment = [1,1915;7459,7503;15373,15544;20396,21061;35838,35877;45968,46098;46986,47041;50210,50275;64458,64502;82156,82219;82629,82665;83172,83235;83855,83904;83981,84016;84605,84631;85033,85066;86548,86579;88345,88442;88955,88996;89516,89558;91976,92004;92535,92596;103922,103960;104186,104227;104802,104840;105339,105450;105530,105558;112261,112287;112640,112674;112707,112746;115328,115439;118556,118582;119072,119103;122605,122630;122750,122778;122882,122998;123336,123369;125143,125187;130180,130213;130608,130649;130718,130759;134565,134622;135349,135399;137404,137439;137793,137883;139906,139950;162280,162342;162403,162482;162661,162781;162852,162896;165559,165611;167782,168518;169425,170047;170680,171718;172001,173184;173793,174953;175508,177219;177734,178058;180001,180098;182110,184000;185183,186407;187102,192000;192777,197372;198927,200000;202540,207388;208001,215995;216001,232000;233000,236000;240525,240905;244001,244321;245441,249982;252057,252101;253428,253482;254680,254719;255140,255176;255717,255864;256135,256988;258586,259853;261782,262713;266651,266695;268850,269370;270046,270084;270532,270969;273331,273372;278573,278619;285484,285512;286180,286222;287099,287143;287309,287393;288780,288819;291787,291837;316226,317047;318137,318313;318978,319643;321559,321601;334199,334375;334438,334471;334890,334928;335916,335979;372092,372735;377551,377571;383083,383122;386796,386834;433573,433603;514100,514160;525648,525711;652363,652545;712705,712760;2978,3154;6479,7036;16498,17176;23583,23995;25506,26211;29605,30170;32562,33144;33417,33998;36151,36762;38320,39641;44001,44776;48001,48703;50938,51401;53054,53566;54376,55014;57495,58176;58629,59114;60122,60381;61903,62630;63349,64137;66374,66437;74591,75168;81675,81722;82250,82281;86578,86638;87802,88711;92828,92889;103419,104000;105183,105254;109885,110514;120933,121587;133465,133499;133605,134281;136001,137079;142218,142867;159712,159772;160001,160749;161562,162047;163223,163920;165025,165544;180089,182119;184001,185192;186355,187149;192001,192808;207384,208000;241557,241888;242731,243254;244323,245466;264624,265246;272275,272692;280267,280754;284001,284504;297928,298587;312952,313840;314470,314850;315615,315659;320052,320719;333694,333719;335551,336000;336323,336800;345495,346168;347148,347705;376001,376574;380001,380980;384170,384803;389839,390434;392619,393577;398532,400000;418532,419073;420001,420571;432952,433509;437917,438547;439314,440000;442667,443383;450556,451079;457831,458283;459699,460287;468001,469512;478309,479374;480001,480641;481430,482380;485140,486160;490922,491538;510836,511458;515301,516000;518866,520000;522264,523667;530968,531452;536885,537644;541895,542297;545879,546488;576901,577574;587341,587377;602935,602966;616140,616768;632001,632663;648718,649241;659137,659826;669398,669896;670556,670939;674796,675213;705288,705802;707771,708000;709054,709547;712001,712383;734497,734912;737390,738101;742341,743087;747091,747692;748291,749104;761995,762727;789191,789792;822952,824000;832001,832582;834393,835606;836401,837015;838387,838936;855519,855987;857745,858222;858857,859423;892130,892905;901189,901945;915527,916000;918067,918600;920896,920964;929146,929633;932221,932800;934414,935108;948726,949241;968511,969149;972949,973364;1000474,1000966;1002382,1002842;1005796,1007049;1017019,1018246;1025008,1025910;1032879,1033534;1035505,1035915;1037519,1039211;1048425,1049023;1053245,1054076;1057522,1057998;1060154,1060214;1065968,1066633;1071134,1071557;1072487,1073265;1077911,1078469;1091188,1091305;1101893,1102466;1127602,1128000;1130195,1130698;1131678,1132310;1133393,1134032;1136342,1136860;1137068,1137754;1143616,1144780;1153202,1153829;1159075,1159761;1167376,1168000;1175513,1176000;1193116,1193813;1230852,1231630;1248272,1248840;1254274,1255197;1266855,1267721;1286624,1287151;1295056,1295662;1313070,1313783;1318820,1319364;1321793,1321861;1332001,1332510;1337172,1337595;1362831,1363291;1374083,1374563;1376581,1377343;1380054,1380596;1383626,1384000;1393847,1394504;1397331,1397883;1410524,1410971;1429003,1429617;1441113,1441708;1476810,1476846;1503024,1503541;1509035,1509544;1514003,1514547;1525154,1525797;1527468,1528000;1535659,1536257;1547263,1547737;1576001,1576590;1588699,1589302;1592793,1593426;1595355,1596101;1604296,1604800;1614307,1614832;1629960,1630590;1642312,1642721;1707301,1707864;1712976,1713491;1716159,1716692;1742540,1743149;1752584,1753149;1771218,1771619;1786341,1786751;1816253,1816786;1819505,1820000;1835255,1836000;1860885,1861558;1880269,1880864;1891933,1892313;1901237,1901848;1926006,1927176;1964659,1965235;1975700,1976268;1981844,1982289;1985301,1985802;2012753,2013208;2031864,2032640;2095193,2095979;2099395,2099901;2100001,2100579;2106309,2107151;2108052,2108437;2110653,2111170;2121637,2122195;2144724,2145184;2192001,2192561;2214554,2215111;2252449,2253052;2262427,2263036;2306785,2307404;2312398,2312907;2336987,2337515;2343231,2343761;2351296,2352518;2355654,2356188;2371766,2372433;2385694,2386267;2387567,2388000;2406914,2407356;2429782,2430345;2449178,2449759;2450237,2450885;2456001,2456808;2504546,2505179;2527072,2527571;2554710,2555533;2560573,2561582;2568001,2568708;2592001,2592469;2595013,2596000;2606444,2607006;2620573,2621141;2670261,2670880;2673086,2673727;2676251,2676932;2680605,2681144;2724001,2724448;2752995,2753566;2754621,2755149;2772001,2772848;2785809,2787033;2793807,2794369;2818909,2820000;2831325,2832000;2857920,2858361;2873785,2874380;2912095,2912563;2917371,2918087;2932291,2932867;2946527,2949077;2960828,2961380;2966100,2967340;2972001,2972657;2981253,2981843;2985116,2985902;3000304,3000843;3005503,3006144;3020748,3021310;3035046,3037259;3047132,3047767;3056001,3056499;3060001,3061052;3068490,3069036;3088001,3088534;3196589,3196918;3197328,3197835;3202925,3203388;3204001,3204674;3221121,3221687;3233718,3234380;3239207,3240000;3242264,3243341;3259440,3260068;3268487,3269036;3280576,3281101;3300850,3301507;3312001,3312464;3355807,3356511;3435929,3436469;3456001,3456598;3474538,3475181;3498212,3498678;3576573,3577203;3619841,3620191;3621482,3621922;3671296,3671780;3686745,3687240;3688643,3689101;3696001,3696434;3754239,3755364;3764057,3764706;3765127,3765730;3767244,3767791;3793215,3793757;3828108,3828633;3861283,3861942;3965358,3965719;3972372,3972792;3996640,3996717;4004296,4004948;4013213,4013797;4021011,4021746;4062667,4063254;4118368,4118842;4121597,4122149;4174954,4175466;4176651,4177257;4209129,4209679;4227745,4228411;4234680,4235245];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1147P %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: 
% FINISHED FINISHED

% 'R1147P' - 3    - 40T  - 32F   - 101/559   - 0.1807   - 9T   - 14F   - 75/430  - 0.1744                   - :)  - Doable, but maybe too many lines.
% 'R1147P' - 1/3  - 40T  - 32F   - 73/283    - 0.2580   - 9T   - 14F   - 54/213  - 0.2535                   - :)  - Doable, but maybe too many lines.
% 'R1147P' - 2/3  - 40T  - 32F   - 11/96     - 0.1146   - 9T   - 14F   -   9/71  - 0.1268                   - :)  - Doable, but maybe too many lines.
% 'R1147P' - 3/3  - 40T  - 32F   - 17/180    - 0.0944   - 9T   - 14F   - 12/146  - 0.0822                   - :)  - Doable, but maybe too many lines.

% Dominated by line noise. Cannot tell which channels are broken without prior filtering. 
% Must be re-referenced prior to line detection.
% Individual session lines show up in combined, so using re-ref combined for line detection.
% Have to throw out grids to preserve 80-150 Hz activity.

% Could do grid specific re-ref.
% LGR is not saveable. LSP and LPT can be re-referenced with one another. But these are parietal.
% So, maybe not worth it to save LSP and LPT

% Good number of trials.
% Interictal spikes, deflections, buzz. Will require intensive cleaning.
% 'LAST1', 'LAST2', 'LAST3', 'LPST1' have a fair amount of IEDs
% Lots of buzz and ambiguous IEDs remain, though was somewhat aggressive in cleaning out little blips. Could add them back in.

% Channel Info:
info.R1147P.badchan.broken = {'LGR64', 'LGR1' ... % big fluctuations
    'LGR*', 'LSP*', 'LPT*'}; % bad line spectra

info.R1147P.badchan.epileptic = {'LDH2', 'LDA2', 'LMST2', 'LDH3', 'LDA3' ... Kahana epileptic
    'LPST6' ... % bad spikes. Confirmed.
    'LMST3', 'LMST4' ... % IEDs and ambiguous slinkies
    }; 
info.R1147P.refchan = {'all'}; %{{'all', '-LSP*', '-LPT*'}, {'LSP*', 'LPT*'}};

% Line Spectra Info:
% z-thresh 0.5 + 1 manual
info.R1147P.FR1.bsfilt.peak      = [60  83.2 100 120 140 166.4 180 200 221.4 240 260 280 300 ...
    160 ...
    ]; % 80]; % from LSP* and LPT*
info.R1147P.FR1.bsfilt.halfbandw = [0.5 0.5  0.5 0.5 0.5 0.5   0.5 0.5 3.6   0.5 0.7 0.5 0.5 ...
    0.5 ...
    ]; % 0.5];
info.R1147P.FR1.bsfilt.edge      = 3.1840;
     
% Bad Segment Info: 
info.R1147P.FR1.session(1).badsegment = [392626,393232;401231,401328;414750,414860;416606,416945;434662,436365;441734,442683;453489,454034;458174,459001;470851,471844;479335,481534;481984,482759;485053,486332;488001,489397;493638,493695;498827,500000;511698,511844;520783,525223;528940,529054;539303,540000;543230,544000;548001,549022;554029,554868;562764,563505;569456,573223;577400,578239;578970,579582;582488,584000;592860,593848;595444,596000;624537,625558;634049,634771;644001,644828;655335,656000;660432,661268;667037,671751;674807,675783;676920,677929;680178,680280;682109,682364;692755,693461;707214,708437;721251,722143;742117,742848;765904,766844;776334,778685;783266,785554;794496,795247;796997,797623;804775,804897;810670,811203;823500,824349;829400,829905;846146,847078;853767,854187;858948,860175;876211,877885;892336,893488;895024,897377;903595,903785;904001,905163;907295,907505;919609,920000;929738,930582;933581,933715;943299,944000;949589,950187;955178,956000;974123,975070;981146,981868;994242,999082;1005057,1005667;1013694,1014022;1020658,1021127;1042254,1042586;1058101,1058796;1065166,1065304;1079464,1080361;1108928,1109691;1112001,1115590;1116666,1116881;1126710,1127336;1162904,1163054;1177364,1178006;1216001,1217639;1264368,1264998;1320130,1321086;1331730,1332316;1336759,1337490;1340912,1344000;1348521,1349264;1366948,1367570;1372936,1373175;1384436,1385066;1410770,1411384;1433138,1433284;1437900,1441215;1468186,1468566;1489130,1489953;1514210,1514441;1517960,1518695;1546533,1549881;1571766,1572788;1580485,1581264;1619754,1620000;1621372,1622171;1652001,1654231;1658339,1658751;1674533,1674675;1701992,1702151;1758178,1759703;1761964,1762538;1768473,1769324;1776001,1778433;1795133,1795670;1813698,1814376;1841307,1841993;1847798,1848244;1884791,1888000;1936521,1937514;1966879,1967630;1984049,1987017;2009464,2010155;2088001,2090163;2097372,2097490;2100001,2101832;2120686,2121679;2122436,2122638;2141859,2142747;2168823,2169236;2169682,2170163;2204852,2208000;2222750,2222989;2267214,2267300;2268001,2268566;2314448,2314977;2400154,2400772;2404158,2404925;2410500,2411433;2420001,2420925;2424001,2424812;2429489,2429929;2433751,2434348;2439020,2440000;2462138,2462719;2528956,2530905;2531077,2531271;2545831,2546538;2556876,2557449;2621799,2622687;2650319,2650755;2681783,2682610;2686379,2689421;2738976,2740615;2784255,2784941;2804299,2804841;2817892,2818473;2859133,2859699;2924247,2926872;2953489,2954308];
info.R1147P.FR1.session(2).badsegment = [330001,331747;334835,335130;335762,336599;340831,342227;343601,345175;353073,353615;357972,358804;369122,370296;376182,376816;391008,394304;456844,457348;462525,463324;494448,494755;495065,497610;523718,524000;552807,553361;564408,564635;592448,596000;608001,609961;620001,620272;629525,629901;631242,631594;645444,645921;648001,649941;704856,706264;744001,745397;805678,807320;810198,812000;830150,832000;871170,872000;946908,948986;950549,952000;958920,961397;1024130,1024413;1149347,1150368;1164324,1168953;1181420,1182195;1190996,1191163;1198105,1198469];
info.R1147P.FR1.session(3).badsegment = [151117,152000;155722,156000;172614,172832;194375,194743;228916,231791;250553,250715;274738,276000;282811,283050;374835,375163;376001,377739;378492,378715;396795,397183;430533,430820;435532,435679;436001,436429;438359,438598;448263,449510;473944,474179;482779,483118;495141,495344;495561,495787;496178,496752;528134,528526;533908,534195;564787,566126;589682,590054;598202,598598;630017,630763;669634,670973;768658,769788;789388,791025;800001,806122;893412,894679;902202,909949;918388,919634;1084299,1084449;1085767,1086663;1110392,1112000;1231915,1233324;1238694,1239062];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1149N %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1149N' - 1    - 39T  - 16F   - 64**/300  - 0.2133   - 29T  - 16F - 47/250 - 0.1880                          - ??? - Done. Expansion. 67 recall.

% ALEX grid is particularly affected by wide line noise, needs to be removed.
% Remaining channels are slinky, periods of high amp slink that will need to be removed.
% Lots of intermittently buzzy channels, hopefully got them all. 
% Both slink episodes and interictal spikes need to be removed. Not the cleanest.
% Re-ref cleans spectra baseline, using re-ref for peak detection.
% Could be a good subject, but perhaps not enough trials will remain after cleaning.
% 'AST3', 'AST4', 'MST2', 'MST3', 'MST4', 'OF*', 'TT*', 'LF*', 'G1', 'G2', 'G3', 'G18', 'G19', 'G2', 'G20', 'G26', 'G27', 'G28', 'G29', 'G3', 'G9' ... % buzzy channels
% IEDs + ambiguous ones, long buzz + ambiguous

% Channel Info:
info.R1149N.badchan.broken = {'ALEX1', 'ALEX8', 'AST2', ... % flatlines, big fluctuations
    'ALEX*' ... % wide line noise. Not worth saving.
    };
info.R1149N.badchan.epileptic = {'PST1', 'TT1', 'MST1', 'MST2', 'AST1', ... % Kahana
    'TT*' ... % oscillation with spikes
    };
info.R1149N.refchan = {'all'};

% Line Spectra Info:
% Session 1/1 z-thresh 0.5 + manual (small)
% with a bunch of channels removed
% info.R1149N.FR1.bsfilt.peak      = [60  120 180 211.6 220.1000 226.8000 240 241.9000 257.1000 272.2000 280 287.3000 300 ...
%     136 196.5];
% info.R1149N.FR1.bsfilt.halfbandw = [0.6 0.5 1   0.5   0.5000 0.5000 1.3000 0.5000 0.5000 0.5000 0.5000 0.5000 1.4000 ...
%     0.5 0.5];
% info.R1149N.FR1.bsfilt.edge      = 3.0980;

% with only TT* removed
info.R1149N.FR1.bsfilt.peak      = [60  120 180 196.5 211.7 219.9 220.2 226.8 240 241.9 257.1 272.1 279.9 287.3 300 ...
    105.8 120.9 136];
info.R1149N.FR1.bsfilt.halfbandw = [0.5 0.5 0.7 0.5   0.5   0.5   0.5   0.5   0.9 0.5   0.5   0.5   0.5   0.5   0.9 ...
    0.5   0.5   0.5];
info.R1149N.FR1.bsfilt.edge      = 3.1840;

% Bad Segment Info:
info.R1149N.FR1.session(1).badsegment = [626178,628000;637077,638433;663872,665116;668739,670481;696001,697223;858641,860000;899831,902896;941783,942626;1055847,1057467;1091379,1092000;1113110,1114973;1123113,1123832;1146182,1148776;1151726,1153687;1177662,1178771;1225057,1226062;1278984,1279489;1414081,1414759;1426186,1426985;1578512,1584373;1665872,1666562;1667520,1669143;1673638,1676724;1678476,1680441;1683097,1683485;1692759,1694199;1714654,1715134;1719729,1720392;1752545,1755779;1765972,1767211;1771516,1773115;1806138,1806751;1828344,1830159;1850093,1851892;1857460,1858090;1888424,1888986;1948118,1954360;1959415,1984000;2006940,2007767;2021198,2024000;2099872,2101019;2101571,2102216;2126271,2127243;2136461,2141151;2154206,2155054;2237364,2242969;2295726,2296413;2308001,2308466;2335948,2336341;2348219,2349530;2378589,2387118;2403807,2404252;2495815,2499187;2555407,2556776;2567194,2568000;2586130,2586594;2677013,2680000;2688029,2691703;2696332,2696965;2705638,2706477;2761384,2764000;2772203,2773570;2819835,2820558;2836610,2837232;2910448,2912000;2943081,2944000;2951460,2952000;2984529,2985272;3005372,3006082;3017231,3018763;3021287,3023816;3040162,3040853;3059057,3059715;3084001,3086989;3090202,3095106;3102198,3103614;3104001,3107517;3114633,3118909;3153351,3153901;3158226,3161300;3241307,3241574;3242702,3244000;3260001,3260941;3262766,3264000;3268001,3269764;3276001,3279711;3285190,3289437;3318561,3320000;3320497,3322582;3366658,3369179;3378275,3379001;3457162,3458393;3488670,3489381;3505130,3506804;3526581,3528881];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1151E %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1151E' - 3    - 7T   - 5F    - 208/756   - 0.2751   - 7T   - 5F    -  202/734 -0.2752                  - :)  - Good pending cleaning. Core.
% 'R1151E' - 1/3  - 7T   - 5F    - 77/300    - 0.2567   - 7T   - 5F    -  76/295 - 0.2576                    - :)  - 
% 'R1151E' - 2/3  - 7T   - 5F    - 83/300    - 0.2767   - 7T   - 5F    -  81/296 -0.2736                    - :)  - 
% 'R1151E' - 3/3  - 7T   - 5F    - 48/156    - 0.3077   - 7T   - 5F    -  45/152 -0.2961                    - :)  -

% Pretty bad noise specific to surface channels. Re-ref before line spectra helps find sharp spectra.
% Using combined re-ref for detecting peaks
% Remaining channels are kinda coherent and slinky, but nothing major.
% No spikes, just occasional buzz. Relatively clean.
% Session 3 goes bad from time 2100 onward, also between 1690 and 1696.
% Great trial number and accuracy, but poor coverage.
% Exceptionally clean. Barely any IDEs, and no buzz.

% TRY THIS SUBJECT FOR PHASE ENCODING. Very curious if channel pairs will be present.

% Channel Info:
info.R1151E.badchan.broken = {'RPHD8', 'LOFMID1' ... sinusoidal noise and fluctuations, session 1
    };

info.R1151E.badchan.epileptic = {'LAMYD1', 'LAMYD2', 'LAMYD3', 'LAHD1', 'LAHD2', 'LAHD3', 'LMHD1', 'LMHD2', 'LMHD3', ... % Kahana
    }; 
info.R1151E.refchan = {'all'};

% Line Spectra Info:
% Lots of line spectra, but baseline is pretty ok. 
info.R1151E.FR1.bsfilt.peak      = [60  180 210.2 215 220.1 300 ...
    100 120 123.7 139.9 239.9 247.3 260];
info.R1151E.FR1.bsfilt.halfbandw = [0.5 0.5 0.5   0.5 0.5   0.5 ...
    0.5 0.5 0.5   0.5   0.5   0.5   0.5];

% Bad Segment Info:
info.R1151E.FR1.session(1).badsegment = [1158351,1158997;1187480,1188000;2215746,2216458;2442105,2445397;2804473,2804651;2821460,2822175;2936114,2936732;2984501,2984957;3211246,3211896;3236166,3236542;3326883,3326993];
info.R1151E.FR1.session(2).badsegment = [443827,444183;580086,580449;592670,592937;1261920,1262280;1350787,1350961;1535335,1535554;1623488,1624000;1781710,1783521;1829077,1829236;2129376,2129695;2540642,2540965];
info.R1151E.FR1.session(3).badsegment = [706948,707650;1130569,1131340;1169130,1169619;1211544,1212191;1282444,1282993;1284473,1285469;1379367,1380000;1477158,1477562;1480279,1480764;1507073,1520000];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1154D %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1154D' - 3    - 39T  - 20F   - 271/900   - 0.3011   - 37T  - 19F   -                       - :)  - *** Core.
% 'R1154D' - 1/3  - 39T  - 20F   - 63/300    - 0.2100   - 37T  - 19F   - 63/300    - 0.2100                     - :)  - 
% 'R1154D' - 2/3  - 39T  - 20F   - 108/300   - 0.3600   - 37T  - 19F   - 103/281 - 0.3665                     - :)  - ***
% 'R1154D' - 3/3  - 39T  - 20F   - 100/300   - 0.3333   - 37T  - 19F   - 94/285 - 0.3298                     - :)  - ***

% No Kahana electrode info available.

% Lots of line spectra, though remaining baseline is flat.
% Needs LP.
% Some buzz that can be removed by re-ref.
% Discrete large events, decent number of slinky channels, decent number of low-amplitude fluctuating channels.
% Using combined session re-ref for line detection, plus manual adding of other peaks from individual sessions
% Nothing that makes me distrust this subject.

% Session 2 is corrupt after 2738 seconds.
% Session 2 still has buzzy episodes after re-ref and LP.
% Very slinky channels in Session 2, might be worse than Session 1.

% First 242 seconds of Session 3 are corrupted.
% Session 3 is very buzzy too.

% Buzzy. No IEDs.

% LTCG* saved by re-referencing separately. From 10/19 to 37/19

% Channel Info:
info.R1154D.badchan.broken = {'LOTD*', 'LTCG23', ... % heavy sinusoidal noise
    'LTCG*', ... % bad line spectra
    'LOFG14' ... % big fluctuations in Session 2
    }; 

info.R1154D.badchan.epileptic = {'LSTG1' ... % intermittent buzz LSTG2
    };
info.R1154D.refchan = {'all'}; % {{'all', '-LTCG*'}, {'LTCG*'}};

% Line Spectra Info: 
info.R1154D.FR1.bsfilt.peak      = [60 120 138.6 172.3 180 200 218.5 220 222.9 225.1 240 260 280 300 ... % combined z-thresh 0.5
    99.9 140 160 205.9 277.2 ... % manual combined
    111.5 ... % manual session 1
    ]; % 80 196.2]; % tiny one from LTCG

info.R1154D.FR1.bsfilt.halfbandw = [0.5 0.5 0.5  0.5   0.5 0.5 0.5   0.7 2.5   0.5   0.5 0.5 0.5 0.5 ...
    0.5  0.5 0.5 0.5   0.5 ...
    0.5 ...
    ]; % 0.5 0.5];

% Bad Segment Info:
info.R1154D.FR1.session(1).badsegment = [492223,495142;2129384,2131856;2332001,2334453;2639109,2642489];
info.R1154D.FR1.session(2).badsegment = [228001,229457;334726,338215;348469,350812;372497,374739;385069,388000;432880,436000;540860,545119;550057,552000;586819,589268;644001,646767;649472,651832;675319,677361;691238,694022;747831,750735;751045,753856;1001299,1004000;1029122,1031138;1035520,1036990;1065102,1067957;1085347,1088000;1158678,1162401;1165726,1169006;1176368,1180000;1260001,1263481;1266585,1268506;1327162,1327590;1410343,1411231;1566279,1570691;1663750,1665276;1744001,1746711;1768094,1772000;1779097,1781433];
info.R1154D.FR1.session(3).badsegment = [530658,535759;536311,540000;540489,543759;548001,550949;554662,555751;564001,566433;634105,636000;641908,644000;660190,664792;739395,741631;742512,744000;768803,769848;850762,852961;857702,858840;863016,866304;1039299,1040760;1041803,1043848;1073900,1076000;1342823,1348000;1359508,1362655;1530404,1533812;1546299,1548000;1552001,1554078;1556001,1557957;1578654,1579888;1826222,1828000;1856598,1857780;1947226,1950884;1956001,1960000;1970198,1972000;2040001,2040712;2141521,2143078];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1162N %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1162N' - 1    - 25T  - 11F   - 77**/300  - 0.2567   - 17T  - 11F - 75/276 - 0.2717                          - :)  - Done. Expansion. 

% No Kahana electrode info available.
% Very clean, only occassional reference noise across channels. WRONG. I
% WAS WRONG. VERY SHITTY.
% Mostly only harmonics in line spectra. Baseline has slight wave to it.
% Line detection on re-ref. 
% Data is ambiguously dirty (can't quite tell where bad things start and stop), but not so bad that this subject is untrustworthy.
% Not as bad.
% info.R1162N.badchan.epileptic = {'AST*', 'ATT*' ... % buzzy and synchronous spikes 'PST2', 'PST3'}; % intermittent buzz 
% Ambiguous swoops and IEDs. Virtually no buzz.

% Channel Info:
info.R1162N.badchan.broken = {'AST2'};
info.R1162N.badchan.epileptic = {'AST1', 'AST2', 'AST3', 'ATT3', 'ATT4', 'ATT5', 'ATT6', 'ATT7', 'ATT8', ... % synchronous spikes on bump
    'ATT1' ... % bleed through from depths
    };
info.R1162N.refchan = {'all'};

% Line Spectra Info:
info.R1162N.FR1.bsfilt.peak      = [60  120 180 239.5 300 ... % Session 1/1 z-thresh 1
    220]; % manual, tiny tiny peak
info.R1162N.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5   0.6 ...
    0.5]; % manual, tiny tiny peak

% Bad Segment Info:
info.R1162N.FR1.session(1).badsegment = [665485,666054;671935,672472;684932,685498;801243,801659;882766,883167;929392,930578;966887,967247;1047569,1048000;1075238,1075578;1152001,1153074;1163605,1164000;1285791,1286376;1661231,1661727;1671311,1672599;1677069,1677776;1717089,1717699;1741283,1741744;1910355,1911005;1958609,1959223;1960928,1961530;1962738,1964000;2106226,2106707;2127077,2127550;2142617,2143820;2151238,2151876;2419129,2419687;2432590,2433361;2446666,2447263;2584763,2586054;2587617,2588000;2709489,2710042;2712541,2713086];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1166D %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1166D' - 3    - 5T   - 38F   - 129/900   - 0.1433   - 5T   - 35F   - 125/870  - 0.1437    - :)  - Done. Core. 
% 'R1166D' - 1/3  - 5T   - 38F   - 30/300    - 0.1000   - 5T   - 35F   - 30/295   - 0.1017    - :)  - 
% 'R1166D' - 2/3  - 5T   - 38F   - 49/300    - 0.1633   - 5T   - 35F   - 47/282   - 0.1667    - :)  - 
% 'R1166D' - 3/3  - 5T   - 38F   - 50/300    - 0.1667   - 5T   - 35F   - 48/293   - 0.1638    - :)  - 

% Seizure onset zone "unreported".
% LFPG seem kinda wonky. Needs re-referencing and LP filter before cleaning. Lots of buzz still.
% Session 2: maybe some slight buzz and "ropiness" on LFPG temporal channels (24, 30-32).
% A few line spectra between 80 and 150Hz, but much smaller with re-ref
% Line detection on re-ref. 
% Buzzy episodes need to be cleaned out.
% No major events or slink, but buzz is worrying. 
% Lots of trials, low accuracy, ok coverage.
% Buzzy. No avoiding the buzz.
% LSFPG* can be re-refed separately. 5/19 to 5/35

% Channel Info:
info.R1166D.badchan.broken = {'LFPG14', 'LFPG15', 'LFPG16', ... % big deflections
    'LSFPG*', ... % bad line spectra
    'LFPG10' ... % big fluctuations in Session 3
    };
info.R1166D.badchan.epileptic = { ...
    'LFPG5', 'LFPG6', 'LFPG7', 'LFPG8'}; % wonky fluctuations together with one another
info.R1166D.refchan = {'all'}; % {{'all', '-LSFPG*'}, {'LSFPG*'}};

% Line Spectra Info:
info.R1166D.FR1.bsfilt.peak      = [60  120 180 200 217.8 218.2 218.8 220.1 223.7 240 300 ...
    100.1 140 160 260 280];
info.R1166D.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5 0.5   0.5   0.5   0.5   1.6   0.5 0.5 ...
    0.5   0.5 0.5 0.5 0.5];
info.R1166D.FR1.bsfilt.edge = 3.1840;

% Bad Segment Info:
info.R1166D.FR1.session(1).badsegment = [20271,22642;467702,472510;607544,607626;620856,622376;717557,722586;1064001,1066534;1160453,1163199;1171198,1175638;1176287,1177518;1284001,1285558;1309480,1311090;1313227,1315408;1331815,1333816;1335637,1335699;1336001,1338006;1429799,1431533;1549158,1552369;1557089,1558671;1771383,1773953;1775274,1776000;1844001,1848000;1878762,1883110;1964831,1968000;1972001,1976000;1976448,1978312;2156372,2158255;2294383,2298634;2310613,2312000;2452001,2452764;2485932,2487384;2500860,2504329;2505428,2505949];
info.R1166D.FR1.session(2).badsegment = [288505,289856;511186,512486;552888,556736;740001,742570;995629,996635;1220594,1223840;1224791,1226711;1300682,1302066;1304618,1306183;1496368,1497260;1506549,1508000;1654371,1656619;2364372,2366304;2368964,2370860;2465271,2467348;2470170,2472965;2485880,2487541;2576706,2579130;2692783,2694401;2793791,2800925];
info.R1166D.FR1.session(3).badsegment = [498605,500204;634779,636000;732162,733558;852259,854981;874895,880000;880537,883687;910130,912873;1040787,1043094;1112549,1114647;1233775,1237405;1244001,1248000;1253924,1254042;1291379,1293699;1304690,1307308;1430125,1438384;1440001,1441659;1442662,1445570;1603335,1606255;1607524,1612000;1716420,1718554;1760307,1764873;1926621,1927570;1987307,1989409;2037932,2040000;2280642,2284000;2405686,2408000];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1167M %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1167M' - 2    - 39T  - 20F   - 166/372   - 0.4462   - 33T  - 18F   - 136/289   - 0.4706     - :)  - Done. Core. 33. Flat slope. 
% 'R1167M' - 1/2    - 39T  - 20F   - 80/192   - 0.4167   - 33T  - 18F   - 56/130  - 0.4113    - :)  - 
% 'R1167M' - 2/2    - 39T  - 20F   - 86/180   - 0.4778   - 33T  - 18F   - 80/159   - 0.5031    - :)  - 

% Line detection on re-ref. Quite a few little line spectra 80-150Hz. 
% LPT channels were wonky, so careful if they are the ones showing the effects.
% Has a bit of buzz still. Could go through and clean these out.
% Ambiguous IEDs and persistent buzz.
% Huge IEDs in depths in Session 2 that bleed into surfaces.
% LAT1-4 have synchronous spikes 

% Channel Info:
info.R1167M.badchan.broken = {'LP7', ... % sinusoidal noise
    'LP8'}; % spiky and large fluctuations

info.R1167M.badchan.epileptic = {'LP1', 'LAT8', 'LAT11', 'LAT12', 'LAT13', 'LAT16', ... % Kahana
    'LAI1', 'LAI2'}; % high frequency noise on top

info.R1167M.refchan = {'all'};

% Line Spectra Info:
% z-thresh 0.45 + manual on combined re-ref. 
info.R1167M.FR1.bsfilt.peak      = [60  100.2 120 180 199.9 220.5 240 259.8 280 300 ...
    95.3 96.9 139.6 140.7 160 181.3];
info.R1167M.FR1.bsfilt.halfbandw = [0.5 0.5   0.5 0.5 0.5   2.9   0.5 0.8   0.5 0.5 ...
    0.5  0.5  0.5   0.5   0.5 0.5];
info.R1167M.FR1.bsfilt.edge = 3.1840;

% Bad Segment Info:
% removing a few more buzzy events
info.R1167M.FR1.session(1).badsegment = [3574,5023;5468,6466;7684,8419;20092,21001;27678,28668;37140,37356;41003,41646;62699,63278;65901,66791;89033,89431;91999,92000;117221,117660;136656,137620;139916,140708;142906,143850;158062,159796;163129,163485;176904,177536;178280,180360;182616,183404;184374,184726;196840,197115;200702,201207;209113,209972;213277,214219;216001,216449;219404,220959;236920,237300;253114,253582;254158,254578;255641,256000;259244,259901;276787,277252;280757,281423;281884,282380;282387,283598;284780,285743;307205,308623;310029,310469;319716,320842;350932,351009;361291,361631;388969,389514;389527,390109;390130,391017;392979,394052;394845,396647;397072,400425;407347,408154;409368,414888;428844,430280;448796,449321;451728,452340;477097,477888;484158,487566;497791,498131;500888,501232;522440,523038;523476,525796;530239,530838;544917,546668;549464,551091;551159,552783;554487,555525;556390,557297;557584,558549;562140,562842;568202,568926;572646,574098;575718,576623;583653,584163;585261,586133;586674,587743;587840,588728;591693,592906;600541,600942;602554,603178;605148,605853;611812,612292;619218,619861;620621,621442;621464,622324;626484,628000;629243,629816;633465,634036;635083,636000;642791,643106;643690,645336;645339,645810;653232,653797;711488,711820;722954,723589;725126,725578;727312,728000;729960,730945;743640,743893;751424,751848;758970,759971;777323,777768;778730,779134;790460,790860;797517,800663;817089,817441;828001,828835;839301,840492;848726,849310;851048,852000;855561,856405;856565,857369;863818,864484;868917,869466;877763,880000;907337,908687;919839,920226;921205,921545;927640,927896;931485,932478;942456,942856;956811,959122;959125,961379;973484,974176;982567,983157;987855,988357;995021,995686;1018851,1019154;1031196,1031888;1060001,1063199;1064666,1064965;1066766,1067399;1082519,1083262;1084001,1084665;1122833,1123525;1137674,1138074;1140299,1143364;1148001,1148475;1149057,1150058;1150174,1150848;1152001,1153308;1169976,1170328;1220513,1220949;1223363,1224324;1244224,1245262;1258919,1259622;1275375,1276000;1286025,1286638;1296151,1296902;1297925,1298592;1344863,1346254;1346844,1347455;1398360,1398953;1402517,1404732;1413788,1415528;1422408,1423844;1430742,1431880;1439836,1440518;1441744,1442148;1496329,1498259;1503432,1504000;1573672,1574388;1588989,1591699;1594698,1595034;1604001,1604612;1607180,1607904;1637113,1637899;1651157,1651654;1663041,1663916;1704674,1705143;1706114,1706731;1716406,1716609;1720831,1724000;1730910,1732000;1742024,1742603;1750967,1753644;1754001,1754562;1826432,1828000;1833041,1833878;1835602,1836443;1888001,1888449;1914645,1916000;1921750,1922738;1936519,1937198;1938019,1938848;1939298,1939923;1940001,1941873;1952208,1952773;1957008,1957982;1975835,1976458;1977872,1978622;2027457,2027804;2029132,2029418;2037909,2038130;2041406,2041843;2052001,2052515;2055811,2056541;2068847,2069706;2077003,2077808];
info.R1167M.FR1.session(2).badsegment = [59923,60574;63558,64259;69264,70353;74277,75329;102823,103434;127279,127974;140041,140469;143352,143708;165656,166595;194006,194872;196796,197321;227866,228426;262261,263082;372457,373615;373872,375779;393207,394044;410005,410590;433952,434667;434867,435163;463230,463880;497213,498318;508046,511313;543768,544568;589987,592945;592977,595287;686174,686594;691394,692094;701613,701974;752090,752441;760151,761310;764501,766046;777127,778127;828060,831995;832001,835990;836001,839998;840001,855998;856001,860000;886379,886792;1001275,1003537;1097158,1097691;1115905,1116544;1140001,1140902;1164041,1164953;1212364,1214106;1216001,1217700;1311371,1312212;1348001,1349012;1365110,1365506;1381464,1384353;1400001,1400476;1418069,1418135;1422694,1424957;1447118,1447458;1607836,1608403;1632952,1633012;1654379,1655022;1704256,1706160;1729771,1731679;1776734,1777310;1810319,1812000;1821799,1823014;1832780,1836000;1836288,1838958;1848208,1848875;1859519,1860319];

% Removing more small IEDs, keeping in high amplitude sections w/out IED shape
% info.R1167M.FR1.session(1).badsegment = [3574,5023;5468,6466;7684,8419;20092,21001;27678,28668;37140,37356;41003,41646;62699,63278;65901,66791;89033,89431;91999,92000;117221,117660;136656,137620;139916,140708;142906,143850;158062,159796;163129,163485;176904,177536;178280,180360;182616,183404;184374,184726;196840,197115;200702,201207;209113,209972;213277,214219;216001,216449;219404,220959;236920,237300;253114,253582;254158,254578;255641,256000;259244,259901;276787,277252;280757,281423;282387,283598;284780,285743;307205,308623;310029,310469;319716,320842;361291,361631;389527,390109;392979,394052;394845,396647;397072,400425;407347,408154;448796,449321;451728,452340;477097,477888;485164,485845;497791,498131;500888,501232;522440,523038;523476,524000;530239,530838;544917,546668;549464,551091;551159,552783;554487,555525;556390,557297;557584,558549;562140,562842;568202,568926;572646,574098;575718,576623;583653,584163;585261,586133;586674,587743;587840,588728;591693,592906;600541,600942;602554,603178;605148,605853;611812,612292;619218,619861;620621,621442;626484,628000;629243,629816;633465,634036;635083,636000;645339,645810;653232,653797;722954,723589;725126,725578;727312,728000;743640,743893;751424,751848;758970,759971;777323,777768;778730,779134;790460,790860;798545,798929;817089,817441;828001,828835;839301,840492;848726,849310;851048,852000;855561,856405;856565,857369;863818,864484;868917,869466;907337,908687;919839,920226;921205,921545;927640,927896;931485,932478;942456,942856;959125,961379;973484,974176;982567,983157;987855,988357;995021,995686;1018851,1019154;1031196,1031888;1064666,1064965;1066766,1067399;1082519,1083262;1084001,1084665;1122833,1123525;1137674,1138074;1141549,1141973;1148001,1148475;1149057,1150058;1169976,1170328;1220513,1220949;1223363,1224324;1244224,1245262;1258919,1259622;1275375,1276000;1286025,1286638;1296151,1296902;1297925,1298592;1344863,1346254;1346844,1347455;1398360,1398953;1413788,1415528;1430742,1431880;1439836,1440518;1441744,1442148;1496329,1498259;1503432,1504000;1573672,1574388;1594698,1595034;1604001,1604612;1607180,1607904;1637113,1637899;1663041,1663916;1704674,1705143;1706114,1706731;1716406,1716609;1721742,1722157;1730910,1732000;1742024,1742603;1750967,1753644;1754001,1754562;1833041,1833878;1835602,1836443;1888001,1888449;1914645,1916000;1921750,1922738;1936519,1937198;1938019,1938848;1939298,1939923;1952208,1952773;1957008,1957982;1975835,1976458;1977872,1978622;2027457,2027804;2029132,2029418;2037909,2038130;2041406,2041843;2052001,2052515;2055811,2056541;2068847,2069706;2077003,2077808];
info.R1167M.FR1.session(2).badsegment = [59923,60574;63558,64259;69264,70353;74277,75329;102823,103434;127279,127974;140041,140469;143352,143708;165656,166595;194006,194872;196796,197321;227866,228426;262261,263082;372457,373615;393207,394044;410005,410590;433952,434667;434867,435163;463230,463880;497213,498318;508046,511313;543768,544568;589987,592945;686174,686594;691394,692094;701613,701974;752090,752441;760151,761310;764501,766046;777127,778127;828060,831995;832001,835990;836001,839998;840001,855998;856001,860000;886379,886792;1097158,1097691;1115905,1116544;1140001,1140902;1164041,1164953;1212364,1214106;1216001,1217700;1311371,1312212;1348001,1349012;1365110,1365506;1400001,1400476;1418069,1418135;1447118,1447458;1607836,1608403;1632952,1633012;1654379,1655022;1704256,1706160;1729771,1731679;1776734,1777310;1810319,1812000;1821799,1823014;1832780,1836000;1836288,1838958;1848208,1848875;1859519,1860319];

% info.R1167M.FR1.session(1).badsegment = [3574,5023;5468,6466;7684,8419;20092,21001;27678,28668;37140,37356;41003,41646;62699,63278;65901,66791;89033,89431;91999,92000;117221,117660;136656,137620;139916,140708;142906,143850;158062,159796;163129,163485;176904,177536;178280,180360;182616,183404;184001,185219;209113,209972;213277,214219;219404,220959;259244,259901;270057,270925;280401,281423;282387,283598;284780,285743;307205,308623;319716,320842;389334,390109;392839,394052;394845,396647;397072,400425;407347,408154;410753,411077;448796,449321;451728,452340;470126,471264;477097,477888;484632,485845;497535,498200;530239,531114;544917,546668;549464,551091;551159,552783;554487,555525;556390,557297;557584,558549;562140,562842;568202,568926;572160,574191;575718,576623;583653,584163;585261,586133;587840,588728;591693,592906;600541,600942;602554,603178;605148,605853;606908,607832;611812,612292;616001,616598;619218,619861;620621,621442;626484,630783;633465,634036;635083,636000;645339,645810;653232,653797;715236,716000;721656,722391;722954,723589;727312,728000;743640,743893;758970,759971;774882,776000;828001,828835;839301,840492;848726,849310;851048,852000;863818,864484;868917,869466;883059,883592;907337,908687;919666,920226;921205,921545;927640,927896;931485,932478;959740,961379;972001,972703;973484,974176;982567,983157;995021,995686;1003231,1004000;1031196,1031888;1058946,1060429;1066766,1067399;1082519,1083262;1083661,1085216;1122833,1123525;1141299,1142536;1148001,1148475;1149057,1150058;1157874,1158837;1223363,1224324;1244224,1245262;1258919,1259622;1278387,1279286;1296151,1296902;1297925,1298592;1303105,1304000;1344863,1346254;1346844,1347455;1378288,1380000;1380210,1380905;1398360,1398953;1413788,1415528;1430742,1431880;1439836,1440518;1441744,1442148;1447690,1448192;1448949,1449491;1455724,1457234;1480608,1481886;1496329,1498259;1503299,1504292;1520423,1521429;1568001,1568416;1573672,1574388;1581436,1582313;1586035,1586697;1587339,1587982;1592941,1593603;1601057,1602203;1603220,1604612;1607180,1607904;1613344,1614060;1614766,1615568;1619000,1619560;1637113,1637899;1651049,1652599;1704187,1705249;1706114,1706731;1707254,1708883;1716406,1716609;1721742,1722157;1727302,1728131;1730910,1732190;1742024,1742603;1750967,1753644;1833041,1833878;1835602,1836443;1866556,1867323;1870594,1871616;1873557,1874275;1914645,1916000;1921750,1922738;1936519,1937198;1938019,1938848;1939298,1939923;1952208,1952773;1957008,1957982;1989807,1990248;1992377,1993832;2005624,2007073;2027457,2027804;2029132,2029418;2037909,2038130;2041406,2041843;2052001,2052515;2055811,2056541;2068847,2069706;2077003,2077808];
% info.R1167M.FR1.session(2).badsegment = [59923,60574;63558,64259;69264,70353;74277,75329;102823,103434;127279,127974;140041,140469;143352,143708;165656,166595;194006,194872;196796,197321;227866,228426;262261,263082;326290,326686;393207,394528;396286,397297;409847,410939;434011,435772;463086,464000;467599,469173;497213,498318;508046,511313;535693,536462;542731,543452;543464,544739;580001,582189;589987,592945;595029,596000;628842,629840;640616,641133;646293,647020;685600,686654;687189,688501;691394,692094;701613,701974;709258,709829;724557,725550;727522,728055;733223,733601;750261,750853;752001,752561;760151,761310;764643,766106;777127,778127;806581,807243;828060,831995;832001,835990;836001,839998;840001,855998;856001,860000;940957,941894;990261,991638;1014148,1014660;1038067,1038590;1097304,1097824;1106930,1107807;1115905,1116544;1121645,1122168;1122869,1124147;1138997,1140902;1142895,1143396;1164041,1164953;1216001,1217700;1220001,1220649;1304001,1304399;1311371,1312212;1329422,1330205;1348001,1349012;1399360,1400948;1447118,1447458;1460001,1460512;1486406,1486987;1505089,1505947;1581997,1582662;1607836,1608403;1632952,1633012;1654379,1655022;1692001,1692558;1704256,1706160;1776734,1777310;1810737,1811420;1821799,1823014;1832780,1836000;1836288,1838958;1848208,1848875;1859519,1860319];

% First cleaning, where I was relatively unaggressive in cleaning out big fluctuations.
% info.R1167M.FR1.session(1).badsegment = [37142,37344;89033,89429;163129,163469;259250,259900;407368,408122;410755,411081;530291,530437;554512,555489;774886,776472;827947,828821;883069,883578;907727,908612;921239,921429;1082561,1083227;1083681,1085205;1223384,1224281;1345533,1346147;1430762,1431691;1496380,1497558;1607234,1607799;1651123,1652462;1707308,1708777;1866573,1867287;1870621,1871562;1873577,1874239;2037952,2038078];
% info.R1167M.FR1.session(2).badsegment = [60001,60466;165698,166300;194025,194836;196835,197284;262307,263038;393231,394324;409884,410917;434073,435727;463097,464000;497222,498260;508763,511304;535722,536436;543769,544591;777198,778018;1038105,1038546;1139014,1140845;1164066,1164917;1215904,1217661;1303928,1304374;1348001,1348978;1399379,1400925;1447166,1447384;1654424,1654977;1704279,1706082;1821823,1822985];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1175N %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% FINISHED FINISHED

% 'R1175N' - 1    - 34T  - 30F   - 68/300  - 0.2267   - 24T  - 27F - 57/265 -   0.2151                       - ??? - Done. 73 recall. 

% No Kahana electrode info available.
% Lots of line noise, but baseline is pretty flat. Some additional, very small lines.
% Fair amount of reference noise, goes away with re-referencing.
% Lots of slinky channels, and some channels with sharp synchronous blips.
% Interictal spikes that will need to be removed.
% Possible that too many trials will be removed.
% Line detect on NON re-ref. Re-ref makes very fat line spectra. Using non-reref lines on re-ref data works well enough.
% Lots of sharp discontinuities, very brief.
% Lots of IEDs, ambiguous.
% Could remove more channels in order to get more trials.
% Was more aggressive in removing channels in order to preserve trials.

% Channel Info:
info.R1175N.badchan.broken    = {'RAT8', 'RPST2', 'RPST3', 'RPST4', 'RPT6', 'RSM6', 'RAF4'};
info.R1175N.badchan.epileptic = {'RAT2', 'RAT3', 'RAT4', 'RAT5', 'RAT6' ... % synchronous spike on bump
    'RAT1', 'RMF3', ... % IEDs isolated to single channels
    'LPST1', 'RAST1', 'RAST2', 'RAST3', 'RAST4' ... % more IEDs
    };
info.R1175N.refchan = {'all'};

% Line Spectra Info:
info.R1175N.FR1.bsfilt.peak      = [60  120 180 220 240 280 300.2 ... % Session 1/1 z-thresh 0.5
    159.9 186 200 216.9 259.9]; % manual
info.R1175N.FR1.bsfilt.halfbandw = [0.6 0.8 1.6 0.5 3   0.5 4.6 ... % Session 1/1 z-thresh 0.5
    0.5   0.5 0.5 0.5   0.5]; % manual
info.R1175N.FR1.bsfilt.edge      = 3.0460;

% Bad Segment Info:
info.R1175N.FR1.session(1).badsegment = [1410383,1411227;1428582,1429357;1448287,1449038;1452001,1452316;1454843,1456000;1464174,1464272;1552997,1553344;1554537,1554578;1555782,1555808;1568747,1569155;1569726,1569816;1573239,1573332;1574029,1574110;1584146,1584832;1656358,1658774;1661714,1662376;1704414,1705359;1727085,1727328;1763593,1764000;1766758,1768000;1804082,1805744;1820741,1821056;1824235,1826066;1863363,1863461;1939452,1940000;1943524,1944296;1946424,1947110;1948166,1948752;1951327,1951739;1954460,1955267;2071784,2072000;2106879,2107836;2122956,2124000;2164247,2165074;2176416,2176542;2206444,2207094;2212275,2212304;2214307,2214441;2254488,2255118;2283315,2283715;2294343,2294642;2298202,2298231;2299117,2299316;2321972,2322759;2437932,2438876;2483819,2484288;2485323,2485985;2490303,2491340;2558553,2559977;2567045,2567812;2571153,2572264;2573872,2573941;2595295,2597226;2605255,2606574;2638557,2639134;2690545,2691271;2700912,2701985;2711682,2712510;2714343,2716000;2736001,2736836;2739669,2740454;2759214,2760000;2786940,2788000;2806779,2807558;2814412,2815064;2904864,2904974;2906154,2906247;2920126,2920806;2933747,2934759;2948328,2949199;2978287,2979154;3054541,3055239;3056416,3056897;3059099,3060000;3092162,3093141;3113098,3113723;3132315,3133167;3180779,3181582;3190920,3191614;3194899,3195840;3244219,3244841;3250381,3252000;3262791,3263495;3270662,3271400;3283686,3284000;3286631,3287263;3311295,3312000;3324805,3325631;3376118,3376901;3441988,3443062;3502811,3503219;3556473,3557288;3579109,3579860;3583544,3584264;3598444,3599223;3602125,3603348;3615540,3616000;3649098,3649844;3656384,3657054;3676436,3680000;3691033,3692000;3696001,3716000;3758553,3759062;3763363,3764000;3798440,3799130;3806178,3806808;3820372,3820994;3838670,3839376;3933787,3934292;3958077,3958384;4036384,4037397;4093335,4094018;4102009,4102562;4118936,4119356;4140981,4141490;4187504,4188000;4225077,4226264;4228616,4228818;4232791,4233437;4234436,4234751;4245041,4246630;4264299,4265937;4281892,4283275;4303900,4304977;4306621,4307481;4337222,4337860;4367488,4368000];

% w/out removing RAST1-4 and LPST1
% info.R1175N.FR1.session(1).badsegment = [1410383,1411227;1426375,1427021;1428582,1429357;1446742,1447703;1448287,1449038;1452001,1452316;1454843,1456000;1464174,1464272;1467375,1467469;1537267,1538038;1552997,1553344;1554537,1554578;1555782,1555808;1568747,1569155;1569726,1569816;1573239,1573332;1574029,1574110;1584146,1584832;1621609,1622155;1637501,1637977;1656110,1660000;1661714,1662376;1704259,1705554;1727085,1727328;1763593,1764000;1766758,1768000;1804082,1805744;1808001,1809042;1820682,1821131;1824235,1826066;1863363,1863461;1936787,1937429;1939452,1940000;1941150,1941598;1943524,1944296;1946424,1947110;1948166,1948752;1951327,1951739;1954460,1955267;2041335,2043110;2071784,2072000;2082775,2082836;2106879,2107836;2122956,2124000;2124884,2126022;2128001,2129042;2139827,2141707;2164247,2165074;2176368,2176909;2206444,2207094;2213118,2215070;2228259,2228978;2244348,2245413;2254488,2255118;2267182,2267868;2283315,2283715;2294343,2294642;2298202,2298231;2299117,2299316;2299379,2299412;2321972,2322759;2374327,2376000;2437932,2438876;2483819,2484288;2485323,2485985;2490303,2491340;2502912,2503824;2558553,2559977;2567045,2567812;2571153,2572264;2573872,2573941;2595295,2598659;2605255,2606574;2638557,2639134;2690545,2691271;2700912,2701985;2711682,2712510;2714343,2716000;2733674,2734397;2736001,2736836;2739669,2740454;2759214,2760000;2786940,2788000;2806779,2807558;2814412,2816000;2819456,2820000;2904864,2904974;2906154,2906247;2906710,2907755;2920126,2921639;2933747,2934759;2948328,2949199;2960743,2961167;2978287,2979154;2984001,2984643;3038585,3038925;3047162,3047275;3048662,3049280;3054541,3055239;3056416,3056897;3058742,3060000;3061867,3062135;3072509,3072889;3092162,3094360;3113098,3113723;3132315,3133167;3166827,3167332;3180779,3181582;3190920,3191614;3194899,3195840;3244219,3244841;3250049,3252000;3262791,3263739;3270662,3271400;3272678,3273348;3283686,3284000;3286335,3287263;3311295,3312000;3324469,3325631;3376118,3376901;3389859,3390268;3424985,3425764;3441988,3443062;3502811,3503219;3504614,3505232;3523698,3524292;3556473,3557288;3579109,3579860;3583544,3584264;3598444,3599223;3602125,3603348;3615540,3616000;3649098,3649844;3656384,3657054;3676436,3680000;3691033,3692000;3696001,3716000;3717726,3717812;3719718,3719812;3758553,3759062;3760767,3764000;3766811,3768000;3798440,3799130;3806178,3806808;3820372,3820994;3828086,3828707;3834742,3835227;3838670,3839376;3850295,3851392;3933787,3934292;3940485,3941481;3958077,3958384;4036384,4037397;4038770,4039574;4093335,4094018;4102009,4102562;4118936,4119356;4140981,4141490;4183432,4184000;4187504,4188000;4225077,4226264;4228533,4228873;4232791,4233437;4234436,4234751;4245041,4246630;4264299,4265937;4281892,4283275;4297609,4298340;4303900,4304977;4306621,4307481;4313702,4314171;4337222,4337860;4367488,4368000;4397323,4398348];
% w/out removing RAT1 and RMF3
% info.R1175N.FR1.session(1).badsegment = [1369206,1369481;1384110,1384349;1391609,1391799;1410383,1411227;1426375,1427021;1428582,1429357;1446823,1446872;1447520,1447570;1448287,1449038;1452001,1452316;1454843,1456000;1464174,1464272;1467375,1467469;1470827,1471287;1495113,1495223;1518138,1518260;1520541,1520655;1533343,1533449;1537267,1538038;1552997,1553344;1554537,1554578;1555782,1555808;1568747,1569155;1569726,1569816;1573239,1573332;1574029,1574110;1584146,1584832;1621609,1622155;1637501,1637977;1656110,1660000;1661714,1662376;1703815,1704000;1704259,1705554;1727085,1727328;1763593,1764000;1766758,1768000;1774194,1774389;1804082,1805744;1807649,1809042;1811033,1812578;1820924,1821026;1824235,1826066;1845743,1845925;1859936,1860000;1863363,1863461;1936787,1937429;1939452,1940000;1941150,1941598;1943524,1944296;1946424,1947110;1948166,1948752;1951657,1952000;1954460,1955267;2024001,2024998;2027367,2027574;2028001,2029119;2041335,2043110;2068473,2068929;2071020,2072000;2072573,2072889;2082775,2082836;2106879,2107836;2122956,2124000;2124884,2126022;2128001,2129042;2139827,2141707;2146101,2146401;2164247,2165074;2176368,2176909;2206444,2207094;2213118,2215070;2228259,2228978;2244348,2245413;2249323,2249502;2250621,2251025;2254488,2255118;2264827,2265836;2267182,2267868;2283315,2283715;2294343,2294642;2298202,2298231;2299117,2299316;2299379,2299412;2321972,2322759;2323186,2323703;2345630,2346276;2374327,2376000;2378210,2378304;2391690,2392000;2408541,2409191;2435835,2435969;2437932,2438876;2446666,2446836;2483819,2484288;2485323,2485985;2490303,2491340;2502912,2503824;2558553,2559977;2561267,2561357;2567045,2567812;2571153,2572264;2573872,2573941;2595295,2598659;2605255,2606574;2638557,2639134;2690545,2691271;2700912,2701985;2711682,2712510;2714343,2716000;2733674,2734397;2736001,2736836;2739669,2740454;2759214,2760000;2786940,2788000;2806779,2807558;2814412,2816000;2819456,2820000;2834601,2834767;2850303,2850735;2904864,2904974;2906154,2906247;2906710,2907755;2914920,2915090;2920126,2921639;2933747,2934759;2948328,2949199;2958633,2958836;2960743,2961167;2978287,2979154;2980291,2981090;2984001,2984643;3005823,3005925;3038585,3038925;3043867,3044000;3047162,3047275;3048662,3049280;3054541,3055239;3056416,3056897;3058742,3060000;3061867,3062135;3072509,3072889;3092162,3094360;3113098,3113723;3126388,3127005;3131085,3131243;3132315,3133167;3166827,3167332;3180779,3181582;3190920,3191614;3194899,3195840;3205541,3206219;3244219,3244841;3250049,3252000;3262791,3263739;3264380,3264961;3266662,3267211;3270662,3271400;3272678,3273348;3275367,3275707;3283686,3284000;3285279,3285429;3286335,3287263;3295597,3295707;3311295,3312000;3314787,3315154;3317049,3317244;3319327,3319723;3324469,3325631;3346766,3346993;3376118,3376901;3389859,3390268;3394049,3394691;3401984,3402086;3424985,3425764;3430125,3430534;3441988,3443062;3502811,3503219;3504614,3505232;3523698,3524292;3556473,3557288;3579109,3579860;3583544,3584264;3598444,3599223;3602125,3603348;3615540,3616000;3634323,3634622;3643266,3643566;3649098,3649844;3656384,3657054;3676436,3680000;3691033,3692000;3696001,3716000;3717726,3717812;3719718,3719812;3724074,3724486;3743347,3743771;3758553,3759062;3760767,3764000;3766811,3768000;3768981,3769195;3770988,3771848;3776948,3777623;3781743,3782022;3798440,3799130;3806178,3806808;3820372,3820994;3828086,3828707;3832924,3833131;3834742,3835227;3838670,3839376;3850295,3851392;3921541,3921731;3926827,3927005;3933787,3934292;3937996,3938155;3940485,3941481;3942835,3943199;3958077,3958384;3972864,3973542;4036384,4037397;4038770,4039574;4093335,4094018;4102009,4102562;4117589,4117873;4118936,4119356;4140981,4141490;4146908,4147727;4172001,4173300;4183432,4184000;4187504,4188264;4189569,4189792;4225077,4226264;4228533,4228873;4232791,4233437;4234436,4234751;4245041,4246630;4252098,4252462;4264299,4265937;4281892,4283275;4297609,4298340;4303900,4304977;4306621,4307481;4313702,4314171;4329331,4329921;4337222,4337860;4367488,4368000;4369388,4370586;4397323,4398348];
end










% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%% R1084T %%%%%% 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Notes: 
% 
% % 'R1084T' - 1    - 2T   - 42F   - 53/300    - 0.1767                                         - !!! - Only 2T. Confirmed.
% 
% % Besides epileptic channels, looks very very clean.
% % Only two temporal channels, confirmed by looking at individual atlas region labels.
% 
% % Channel Info:
% info.R1084T.badchan.broken = {'PG37', 'PG45' ... sinusoidal noise
%     };
% info.R1084T.badchan.epileptic = {'PS3', ... % Kahana
%     'PS1', 'PS2', 'PS4', 'PS5', 'PS6', 'PG41', 'PG42', 'PG43', 'PG44' ... % follow Kahana bad channel closely
%     }; 
% 
% % Line Spectra Info:
% % Session 1/1 z-thresh 0.5 + manual (tiny)
% info.R1084T.FR1.bsfilt.peak      = [60 93.5 120 180.1 187 218.2 240 249.4 280.5 298.8 300.1 ...
%     155.8]; % manual
% info.R1084T.FR1.bsfilt.halfbandw = [1  0.5  0.5 0.9   0.5 0.5   0.5 0.5   0.5   0.5   1.8 ...
%     0.5]; % manual
% 
% % Bad Segment Info:

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%% R1100D %%%%%% 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Notes: 
% 
% % 'R1100D' - 3    - 26T  - 39F   - 11**/372  - 0.0296   -                                     - !!! - Too few correct trials.
% 
% % Not enough trials. Not even worth it.
% 
% % Channel Info:
% info.R1100D.badchan.broken = {
%     };
% info.R1100D.badchan.epileptic = {
%     }; 
% 
% % Line Spectra Info:

% Bad Segment Info:
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%% R1129D %%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% % 'R1129D' - 2    - 0T   - 52F   - 40/228    - 0.1754                                         - !!! - No T before clean. Confirmed.
% 
% % No T. Confirmed.
% 
% info.R1129D.badchan.broken = {
%     };
% info.R1129D.badchan.epileptic = {
%     }; 

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%% R1155D %%%%%% 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Notes: 
% 
% % 'R1155D' - 1    - 1T - 59F   - 33/120  - 0.2750                                         - !!! - Only 1T. Confirmed.
% 
% % Channel Info:
% info.R1155D.badchan.broken = {
%     };
% info.R1155D.badchan.epileptic = {
%     }; 

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%% R1156D %%%%%% 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% % 'R1156D' - 3    - 7T   - 98F   - 215/900   - 0.2389   - 7T   - 53F                          - !!! - All temporal channels bad noise.
% % 'R1156D' - 1/3  - 7T   - 98F   - 63/300    - 0.2100   - 7T   - 53F                          - !!! - 
% % 'R1156D' - 2/3  - 7T   - 98F   - 74/300    - 0.2467   - 7T   - 53F                          - !!! - 
% % 'R1156D' - 3/3  - 7T   - 98F   - 78/300    - 0.2600   - 7T   - 53F                          - !!! - 
% 
% % No Kahana electrode info available.
% % Different grids are differentially affected by line noise. Will need
% % to re-reference some channels separately from one another in order to
% % find signal.
% 
% % Session 1 is corrupt after 3219 seconds.
% % A TON of relatively wide line spectra, especially 80-150Hz.
% % Line spectra not cleaned. Not sure if it is worth it considering the number of notches needed.
% 
% % Bad grids are LAF, LIHG, LPF, RFLG, ROFS, RPS
% 
% % OK grids that still need re-ref help are RFG, RIHG, RFPS; RFG1 should be
% % thrown out.
% 
% % Can potentially save RTS* (the only grid with temporal channels) by re-ref separately.
% 
% info.R1156D.badchan.broken = {'RFG1', 'LAF*', 'LIHG*', 'LPF*', 'RFLG*', 'ROFS*', 'RPS*'};
% info.R1156D.badchan.epileptic = {};
% info.R1156D.refchan = {{'RFPS*'}, {'RIHG*'}, {'RFG*'}, {'RTS*'}};
% 
% info.R1156D.FR1.bsfilt.peak = [60 120 180 200 219.3000 220.1000 224 259.9000 300 ...
%     80 100 112 140 160 240 269.8 280];
% info.R1156D.FR1.bsfilt.halfbandw = [0.5000 0.5000 0.5000 0.5000 0.5000 0.5000 0.5000 0.6000 0.5000 ...
%     05 0.5 0.5 0.5 0.5 0.5 0.5   0.5];
% 
% [60 100 120 140 179.4000 180 200 219.9000 224.9000 240 260.1000 269.8000 280 300 ...
%     79.7 112.4 160.1 172.3];
% [0.5000 0.5000 0.5000 0.7000 0.5000 0.7000 0.5000 1 0.5000 0.5000 1.1000 0.5000 0.5000 0.5000];

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%% R1159P %%%%%% 
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% % 'R1159P' - 1    - 42T  - 47F   - 40/168    - 0.2381                                         - !!! - All temporal channels bad noise.
% 
% % REALLY REALLY SHITTY AND I CAN'T EVEN RIGHT NOW
% % Awful, awful line spectra. Notch and LP filter help. Lots of broken channels, not sure if I got them all.
% % Re-referencing adds little spikes everywhere, and there's bad spikes everywhere too.
% 
% info.R1159P.badchan.broken = {'LG38', 'LG49', 'LG64', 'LG33', 'LG34', 'LG35', 'LG36', 'LG56', 'LO5', 'LG1', 'LG32', 'LG24', 'LG31', 'LG16' ... floor/ceiling
%     };
% 
% info.R1159P.badchan.epileptic = {'RDA1', 'RDA2', 'RDA3', 'RDA4', 'RDH1', 'RDH2', 'RDH3', 'RDH4' ... % Kahana
%     };


% origunclean = {'R1162N', 'R1033D', 'R1156D', 'R1149N', 'R1175N', 'R1154D', 'R1068J', 'R1159P', 'R1080E', 'R1135E', 'R1147P'};








%%%%%% R1068J %%%%%
% Looks funny, but relatively clean. Reference noise in grids RPT and RF go
% haywire by themselves, might need to re-reference individually.
% info.R1068J.FR1.session(1).badchan.broken = {'RAMY7', 'RAMY8', 'RATA1', 'RPTA1'};
% info.R1068J.FR1.session(2).badchan.broken = {'RAMY7', 'RAMY8', 'RATA1', 'RPTA1'};
% info.R1068J.FR1.session(3).badchan.broken = {'RAMY7', 'RAMY8', 'RATA1', 'RPTA1'};




function info = kah_info(varargin)

% KAH_INFO loads path, experiment, demographic, and electrode info for subjects in the RAM (Kahana) dataset.
% Information about line spectra and epileptic channels and segments is hardcoded below for preprocessed subjects.
% NOTE: artifact info is specific to experiment FR1 and surface channels only. Depth channels were not closely examined.
% NOTE: as of August 2018, depth channels were examined for IEDs. All trials with discernible IEDs were marked.
% Depth channels may or may not be marked as broken.
%
% Usage:
%   info = kah_info('all') returns information for all available subjects in the release specified below ('r1' currently).
%   For this usage, TSCC cluster storage must be available.
%
%   info = kah_info(subjects) returns information for the subjects whose IDs are listed in the cell array subjects.
%   For this usage, data from DATAHD (personal hard drive) is loaded if available, and from the cluster otherwise.
%
%   info = kah_info() returns information for a subset of subjects, hardcoded below.
%   For this usage, data from DATAHD (personal hard drive) is loaded if available, and from the cluster otherwise.

warning off

info = struct;

% Subjects with age >= 18, FR1, at least 3 LTL/lPFC
info.subjsubset = {'R1020J', 'R1034D', 'R1045E', 'R1059J', 'R1075J', 'R1080E', 'R1142N', 'R1149N', 'R1154D', 'R1162N', 'R1166D', 'R1167M', 'R1175N', ... % original
    'R1001P', 'R1003P', 'R1006P', 'R1018P', 'R1036M', 'R1039M', 'R1060M', 'R1066P', 'R1067P', 'R1069M', 'R1086M', 'R1089P', 'R1112M', 'R1136N', 'R1177M'}; % additional

% Original subjects
% info.subjsubset = {'R1020J' 'R1032D' 'R1033D' 'R1034D' 'R1045E' 'R1059J' 'R1075J' 'R1080E' 'R1120E' 'R1135E' ...
%     'R1142N' 'R1147P' 'R1149N' 'R1151E' 'R1154D' 'R1162N' 'R1166D' 'R1167M' 'R1175N'};
    
% Set path to where source files are.
info.path.src = '/Users/Rogue/Documents/Research/Projects/KAH/code/';
cd(info.path.src)

% Set path to where to save CSV files to.
info.path.csv = '/Users/Rogue/Documents/Research/Projects/KAH/csv/';

% Set path to Kahana folder on shared VoytekLab server.
hdpath = '/Volumes/DATAHD/KAHANA/';
clusterpath = '/Volumes/voyteklab/common/data2/kahana_ecog_RAMphase1/';

% Use the cluster path if info for all subjects is desired.
if nargin > 0 && strcmpi(varargin{1}, 'all')
    if exist(clusterpath, 'dir')
        info.path.kah = clusterpath;
    else
        error('To load info for all subjects, cluster storage must be available.')
    end
    
% Otherwise, use personal hard drive if available, cluster path otherwise.
else    
    if exist(hdpath, 'dir')
        info.path.kah = hdpath;
    elseif exist(clusterpath, 'dir')
        info.path.kah = clusterpath;
    else
        error('Neither your personal hard drive nor cluster storage is available.')
    end
end

% Set path to .csv file with demographic information.
info.path.demfile = [info.path.kah 'Release_Metadata_20160930/RAM_subject_demographics.csv'];

% Set current release of Kahana data.
info.release = 'r1';

% Set path to experiment data.
info.path.exp = [info.path.kah 'session_data/experiment_data/protocols/' info.release '/subjects/'];

% Set path to anatomical data.
info.path.surf = [info.path.kah 'session_data/surfaces/'];

% Set path to where processed data will be saved.
info.path.processed.hd      = '/Volumes/DATAHD/Active/KAH/';
info.path.processed.cluster = '/Volumes/voyteklab/tamtra/data/KAH/';

% Get info from demographic file.
demfile = fopen(info.path.demfile);
deminfo = textscan(demfile, '%s %s %f %s %s %s %s %s %s %s %s %s', 'delimiter', ',', 'headerlines', 1);
fclose(demfile);

% Get all subject identifiers, if desired. Overrides any hardcoded subjects above.
if nargin > 0 && strcmpi(varargin{1}, 'all')
    info.subj = extractfield(dir(info.path.exp), 'name');
    info.subj(contains(info.subj, '.')) = [];
elseif nargin > 0
    info.subj = varargin{1};
else
    info.subj = info.subjsubset;
end

% Get gender, ages, and handedness of all subjects.
[info.gender, info.hand] = deal(cell(size(info.subj)));
info.age = nan(size(info.subj));
info.subj = info.subj(:); info.gender = info.gender(:); info.hand = info.hand(:); info.age = info.age(:); 

for isubj = 1:numel(info.subj)
    info.gender(isubj) = deminfo{2}(strcmpi(info.subj{isubj}, deminfo{1}));
    info.age(isubj) = deminfo{3}(strcmpi(info.subj{isubj}, deminfo{1}));
    info.hand(isubj) = deminfo{12}(strcmpi(info.subj{isubj}, deminfo{1}));
end

% Load anatomical atlases used for electrode region labelling.
talatlas = ft_read_atlas([info.path.src 'atlasread/TTatlas+tlrc.HEAD']);
mniatlas = ft_read_atlas([info.path.src 'atlasread/ROI_MNI_V4.nii']);

% For each subject, extract anatomical, channel, and electrophysiological info.
for isubj = 1:numel(info.subj)
    
    % Get current subject identifier.
    subject = info.subj{isubj};
    disp([num2str(isubj) ' ' subject])

    % Get path for left- and right-hemisphere pial surf files.
    info.(subject).lsurffile = [info.path.surf subject '/surf/lh.pial'];
    info.(subject).rsurffile = [info.path.surf subject '/surf/rh.pial'];

    % Get path for file with notes for each electrode.
    info.(subject).electrodenotes = [info.path.kah 'Release_Metadata_20160930/electrode_categories/electrode_categories_' subject '.txt'];
    
    % Open file.
    fileID = fopen(info.(subject).electrodenotes);
    electrodenotes = textscan(fileID, '%s');
    electrodenotes = upper(electrodenotes{1});
    info.(subject).electrodenotes = electrodenotes;
    
    % Find bad channels (after Seizure Onset Zone heading and before Interictal)
    info.(subject).badchan.kahana = {};
    onset = find(contains(electrodenotes, 'ONSET'), 1);
    interictal = find(strcmpi('interictal', electrodenotes), 1);
    
    if ~isempty(onset) && ~isempty(interictal)
        epilepticchans = electrodenotes(onset + 1:interictal - 1);
        epilepticchans(contains(epilepticchans, 'ZONE')) = [];
        epilepticchans(contains(epilepticchans, 'UNREPORTED')) = [];
        info.(subject).badchan.kahana = epilepticchans;
    end
    
    % Hard-code some subjects with wonky files.
    info.R1118N.badchan.kahana = {'LID2', 'LID3', 'LID4', 'PPST3', 'PPST4', 'TT1', 'AST1', 'MST1', 'PST1', 'G12'};
    info.R1169P.badchan.kahana = {'RPF*', 'RH*', 'LAF*'};
    info.R1157C.badchan.kahana = {'A1', 'A10', 'A11', 'A12', 'A13', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'IP*'};

    % Get experiment-data path for current subject.
    subjpathcurr = [info.path.exp subject '/'];
            
    % Get subject age.
    info.(subject).age = info.age(isubj);
    
    % Get path for contacts.json and get all contact information.
    info.(subject).contactsfile = [subjpathcurr 'localizations/0/montages/0/neuroradiology/current_processed/contacts.json'];
    contacts = loadjson(info.(subject).contactsfile);
    contacts = contacts.(subject).contacts;
    
    % Get labels for all channels.
    info.(subject).allchan.label = fieldnames(contacts);
    
    % Get info for each channel.
    for ichan = 1:length(info.(subject).allchan.label)
        % Get current channel. 
        chancurr = contacts.(info.(subject).allchan.label{ichan});
        
        % Get channel type (grid, strip, depth).
        info.(subject).allchan.type{ichan} = chancurr.type;
         
        % Get atlas-specific information.
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
            info.(subject).allchan.(atlases{iatlas}).region{ichan} = atlascurr.region;
            
            % Convert xyz coordinates to double, if necessary (due to NaNs in coordinates).
            coords = {'x', 'y', 'z'};
            for icoord = 1:length(coords)
                if ischar(atlascurr.(coords{icoord}))
                    atlascurr.(coords{icoord}) = str2double(atlascurr.(coords{icoord}));
                end
            end
            
            % Extract xyz coordinates.
            info.(subject).allchan.(atlases{iatlas}).xyz(ichan,:) = [atlascurr.x, atlascurr.y, atlascurr.z];
        end
        
        % Get left/right hemisphere.
        info.(subject).allchan.lefthemisphere(ichan) = info.(subject).allchan.ind.xyz(ichan, 1) < 0; % strcmpi('l', info.(subject).allchan.label{ichan}(1));
        
        % Get top anatomical label from MNI atlas.
        try
            mnilabel = lower(atlas_lookup(mniatlas, info.(subject).allchan.mni.xyz(ichan,:), 'inputcoord', 'mni', 'queryrange', 3));
            mnilabel = mnilabel{1};
        catch
            mnilabel = 'NA'; % if no label or atlas was found.
        end
        info.(subject).allchan.mni.region{ichan} = mnilabel;
        
        % Get top anatomical label from TAL atlas.
        try
            tallabel = lower(atlas_lookup(talatlas, info.(subject).allchan.tal.xyz(ichan,:), 'inputcoord', 'tal', 'queryrange', 3));
            tallabel = tallabel{1};
        catch
            tallabel = 'NA'; % if no label or atlas was found.
        end
        info.(subject).allchan.tal.region{ichan} = tallabel;
        
        % Get average anatomical annotations from Kahana group.
        avglabel = lower(info.(subject).allchan.avg.region{ichan});
        
        % Get individual anatomical annotations from Kahana group.
        indlabel = lower(info.(subject).allchan.ind.region{ichan});
        
        % Set terms to search for in region labels to map to lobes.
        frontalterms = {'frontal', 'opercularis', 'triangularis', 'precentral', 'rectal', 'rectus', 'orbital'};
        temporalterms = {'temporal', 'fusiform', 'hippocamp', 'bankssts', 'entorhinal'};
        
        % Determine lobe location based on individual labels only.
        frontal = contains(indlabel, frontalterms);
        temporal = contains(indlabel, temporalterms);
        
        if frontal
            info.(subject).allchan.lobe{ichan} = 'F';
        elseif temporal
            info.(subject).allchan.lobe{ichan} = 'T';
        else
            info.(subject).allchan.lobe{ichan} = 'N';
        end
        
        % Set terms to search for in region labels to map to sub-lobes.
        sublobe_regions = struct;
        sublobe_regions.mtl = {'hippocamp', 'entorhin', 'uncus'};
        sublobe_regions.ltl = {'temporal', 'heschl', 'bankssts', 'brodmann area 20', 'brodmann area 21'};
        sublobe_regions.mpfc = {'orbito', 'rectal', 'rectus', 'olfactory', 'brodmann area 25'};
        sublobe_regions.lpfc = {'frontal', 'opercularis', 'triangularis', 'brodmann area 47', 'orbitalis'};
        sublobe_regions.occipital = {'occipit', 'lingual', 'cuneus', 'calcarine', 'fusiform'};
        sublobe_regions.parietal = {'pariet', 'postcentral', 'supramarginal', 'angular'};
        sublobe_regions.motor = {'precentral', 'paracentral', 'motor', 'rolandic'};
        sublobe_regions.limbic = {'cingulate', 'cingulum', 'subcallosal gyrus', 'amygdala'};
        sublobe_regions.insula = {'insula', 'claustrum'};
        sublobe_regions.striatum = {'caudate', 'putamen', 'lentiform', 'pallidum'};
        sublobe_regions.thalamus = {'pulvinar', 'thalamus'};
        sublobe_regions.cerebellum = {'culmen', 'declive', 'cerebelum', 'vermis'};

        info.sublobe_regions = sublobe_regions;
        
        % Names of possible sublobes.
        sublobes = fieldnames(sublobe_regions);
        
        % Find sublobe for current channel by going through each list of potential regions.
        info.(subject).allchan.sublobe{ichan} = 'NA';
        for isublobe = 1:length(sublobes)
            subcurr = sublobes{isublobe};
            
            % Only proceed if a label has not already been found. 
            if strcmpi(info.(subject).allchan.sublobe{ichan}, 'NA')
                % Use individual label if possible, MNI otherwise.
                if strcmpi(indlabel, 'NA')
                    atlas_use = mnilabel;
                else
                    atlas_use = indlabel;
                end
                
                % Compare current region to list of potential regions for this sublobe.
                if contains(atlas_use, sublobe_regions.(subcurr))
                    info.(subject).allchan.sublobe{ichan} = subcurr;
                end
            end
        end
 
        % Determine lobe location based on majority vote across individual, MNI, and TAL.
        regions = {indlabel, mnilabel, tallabel};
        frontal = contains(regions, frontalterms);
        temporal = contains(regions, temporalterms);
        nolabel = strcmpi('NA', regions);
        
        if sum(frontal) > (sum(~nolabel)/2)
            info.(subject).allchan.sublobe_majority{ichan} = 'F';
        elseif sum(temporal) > (sum(~nolabel)/2)
            info.(subject).allchan.sublobe_majority{ichan} = 'T';
        else
            info.(subject).allchan.sublobe_majority{ichan} = 'NA';
        end
    end
    
    % Re-format to column vectors.
    info.(subject).allchan.type = info.(subject).allchan.type(:);
    info.(subject).allchan.lefthemisphere = info.(subject).allchan.lefthemisphere(:);
    info.(subject).allchan.lobe = info.(subject).allchan.lobe(:);
    info.(subject).allchan.sublobe_majority = info.(subject).allchan.sublobe_majority(:);
    info.(subject).allchan.sublobe = info.(subject).allchan.sublobe(:);
    for iatlas = 1:length(atlases)
        info.(subject).allchan.(atlases{iatlas}).region = info.(subject).allchan.(atlases{iatlas}).region(:);
    end
    
    % Get experiments performed.
    experiments = extractfield(dir([subjpathcurr 'experiments/']), 'name');
    experiments(contains(experiments, '.')) = [];
    
    % Get experiment path info.
    for iexp = 1:numel(experiments)
        % Get current experiment path.
        expcurr = experiments{iexp};
        exppathcurr = [subjpathcurr 'experiments/' expcurr '/sessions/'];
        
        % Get session numbers.
        sessions = extractfield(dir(exppathcurr), 'name');
        sessions(contains(sessions, '.')) = [];
        
        % Get header file, data directory, and event file per session.
        for isess = 1:numel(sessions)
            info.(subject).(expcurr).session(isess).headerfile = [exppathcurr sessions{isess} '/behavioral/current_processed/index.json'];
            info.(subject).(expcurr).session(isess).datadir    = [exppathcurr sessions{isess} '/ephys/current_processed/noreref/'];
            info.(subject).(expcurr).session(isess).eventfile  = [exppathcurr sessions{isess} '/behavioral/current_processed/task_events.json'];
        end
    end
    
    % Get sampling rate from sources.json file.
    sourcesfile = [exppathcurr sessions{isess} '/ephys/current_processed/sources.json'];
    try
        sources = loadjson(sourcesfile);
    catch
        info.(subject).fs = 0; % if sources file not found.
        continue
    end
    sourcesfield = fieldnames(sources);
    info.(subject).fs = sources.(sourcesfield{1}).sample_rate;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%  Subject - Sess - LTL  - LPFC  - Corr./All - Acc.     - Temp - Front - Corr./All - Acc.     - BAD - Notes

%%% COMPLETE %%%
% Original
% 'R1020J' - 1    - 24T  - 21F   - 114/300   - 0.3800   - 8T   - 18F   - 102/279   - 0.36559  - :)  - Done. Confirmed.

% 'R1034D' - 3    - 10T  - 49F   - 48/528    - 0.0909   - 4T   - 41F   - 40/466    - 0.0858   - :)  - Done. Confirmed.

% 'R1045E' - 1    - 16T  - 18F   - 98/300    - 0.3267   - 9T  - 17F    - 76/232    - 0.32759  - :)  - Done. Confirmed.

% 'R1059J' - 2    - 41T  - 42F   - 36/444    - 0.0811   - 16T  - 34F   - 30/315    - 0.0952   - :)  - Done. Confirmed.

% 'R1075J' - 2    - 5T   - 72F   - 150/600   - 0.2500   - 5T   - 25F   - 134/557   - 0.2406   - :)  - Done. Confirmed.

% 'R1080E' - 2    - 6T   - 5F    - 107/384   - 0.2786   - 6T   - 4F    - 104/368   - 0.2826   - :)  - Done. Confirmed.

% 'R1142N' - 1    - 17T  - 36F   - 48/300    - 0.1600   - 16T  - 33F   - 39/225    - 0.17333  - :)  - Done. Confirmed.

% 'R1149N' - 1    - 33T  - 9F    - 64/300    - 0.2133   - 4T   - 9F    - 47/246    - 0.19106  - :)  - Done. Confirmed.

% 'R1154D' - 3    - 34T  - 12F   - 271/900   - 0.3011   - 4T   - 11F   - 231/759   - 0.3043   - :)  - Done. Confirmed.

% 'R1162N' - 1    - 23T  - 8F    - 77/300    - 0.2567   - 19T  - 8F    - 54/195    - 0.27692  - :)  - Done. Confirmed.

% 'R1166D' - 3    - 5T   - 31F   - 129/900   - 0.1433   - 5T   - 17F   - 120/844   - 0.1422   - :)  - Done. Confirmed.

% 'R1167M' - 2    - 40T  - 12F   - 166/372   - 0.4462   - 7T   - 12F   - 127/276   - 0.4601   - :)  - Done. Confirmed.

% 'R1175N' - 1    - 32T  - 25F   - 68/300    - 0.2267   - 6T   - 3F    - 41/217    - 0.18894  - :)  - Done. Confirmed.

% Additional
% 'R1001P' - 2    - 9T   - 11F   - 115/600   - 0.1917   - 5T   - 11F   - 52/258    - 0.20155  - :)  - Done. Can only use Session 2.

% 'R1003P' - 2    - 25T  - 40F   - 187/564   - 0.3316   - 13T  - 35F   - 153/469   - 0.3262   - :)  - Done.

% 'R1006P' - 2    - 33T  - 21F   - 154/480   - 0.3208   - 20T  - 10F   - 41/132    - 0.31061  - :)  - Done. Can only use Session 2.

% 'R1018P' - 1    - 17T  - 38F   - 67/300    - 0.2233   - 11T  - 38F   - 64/273    - 0.23443  - :)  - Done.

% 'R1036M' - 1    - 31T  - 14F   - 49/300    - 0.1633   - 10T  - 14F   - 44/242    - 0.18182  - :)  - Done.

% 'R1039M' - 1    - 13T  - 42F   - 48/216    - 0.2222   - 13T  - 40F   - 47/192    - 0.24479  - :)  - Done.

% 'R1060M' - 4    - 21T  - 27F   - 328/1080  - 0.3037   - 3T   - 18F   - 217/696   - 0.3118   - :)  - Done.

% 'R1066P' - 4    - 13T  - 3F    - 339/1020  - 0.3324   - 6T   - 3F    - 286/799   - 0.3579   - :)  - Done.

% 'R1067P' - 3    - 33T  - 31F   - 132/768   - 0.1719   - 8T   - 29F   - 68/436    - 0.1560   - :)  - Done.

% 'R1069M' - 1    - 7T   - 31F   - 86/300    - 0.2867   - 7T   - 20F   - 79/281    - 0.28114  - :)  - Done.

% 'R1086M' - 1    - 33T  - 23F   - 54/180    - 0.3000   - 32T  - 22F   - 30/80     - 0.375    - :)  - Done.

% 'R1089P' - 1    - 35T  - 14F   - 48/300    - 0.1600   - 6T   - 13F   - 34/216    - 0.15741  - :)  - Done. After re-clean and keeping some channels, ok.

% 'R1112M' - 3    - 20T  - 7F    - 79/624    - 0.1266   - 9T   - 7F    - 56/389    - 0.1440   - :)  - Done. Very unclean. 

% 'R1136N' - 2    - 43T  - 13F   - 119/600   - 0.1983   - 28T  - 10F   - 71/271    - 0.26199  - :)  - Only Session 2.

% 'R1177M' - 2    - 31T  - 14F   - 95/396    - 0.2399   - 20T  - 7F    - 78/330    - 0.2364   - :)  - Done.

% Not Usable

% 'R1002P' - 2    - 18T  - 23F   - 234/600   - 0.39     - 2T   - 22F   - 109/277   - 0.3935   - :(  - Not enough LTL after cleaning. Can only use Session 2.

% 'R1032D' - 1    - 14T  - 8F    - 95/300    - 0.3167   - 1T   - 4F                           - :(  - IED across all T. Confirmed.

% 'R1033D' - 1    - 18T  - 11F   - 23/108    - 0.2130   - 6T   - 11F   - 13/76     - 0.17105  - :(  - Too few trials. Really unclean.

% 'R1042M' - 1    - 27T  - 10F   - 189/300   - 0.6300   - 15T  - 10F   - 177/270   - 0.65556  - :(  - Great performance, but constant IED. Unsalvageable.

% 'R1050M' - 1    - 23T  - 0F    - 126/300   - 0.4200   - 18T  - 0F    - 65/145    - 0.44828  - :(  - Not enough lPFC before cleaning.

% 'R1053M' - 1    - 26T  - 17F   - 32/180    - 0.1778   - 2T   - 16F   - 29/159    - 0.18239  - :(  - Too many T removed.

% 'R1102P' - 1    - 16T  - 22F   - 76/300    - 0.2533   - 0T   - 16F                          - :(  - Too many T removed. 

% 'R1120E' - 2    - 11T  - 0F    - 207/600   - 0.3450   - 5T   - 0F    - 207/599   - 0.3456   - :(  - Not enough lPFC before cleaning. 

% 'R1127P' - 1    - 6T   - 13F   - 54/300    - 0.1800   - 2T   - 13F                          - :(  - Too many T removed. 

% 'R1128E' - 1    - 6T   - 7F    - 141/300   - 0.4700   - 2T   - 6F                           - :(  - Not enough T after cleaning.

% 'R1135E' - 4    - 6T   - 9F    - 107/1200  - 0.0892   - 5T   - 8F    - 31/370    - 0.0838   - :(  - Lesions + bad T. 

% 'R1147P' - 3    - 39T  - 8F    - 101/559   - 0.1807   - 8T   - 8F    - 69/401    - 0.1721   - :(  - Not enough LTL before cleaning. Not salvageable.

% 'R1151E' - 3    - 7T   - 0F    - 208/756   - 0.2751   - 7T   - 0F    - 202/742   - 0.2722   - :(  - Not enough lPFC before cleaning.

% 'R1121M' - 8    - 12T  - 45F   - 92/468    - 0.1966   -                                     - :(  - Did not do distractor tasks. Seizures. 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1177M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Bad reference noise, re-ref fixes
% LTL depth electrode seizure onset
% IEDs in LPID and LPMD, no spread. Other channels have odd little wavy episodes, but probably not going to mark them.
% In Session 2, some IEDs that extend across all channels. Not easy to isolate and not prominent. Leaving it be. 
% Cleaning strategy. Marking trial if extends past LPID and LPMD, leaving in otherwise. Too ambiguous if mark all LPID/LPMD
% Lots of odd channel breaks.

% Channel Info:
info.R1177M.badchan.broken = {'LG62', 'LG21', 'LG27', 'LFS2', 'LG12', 'LG47', 'LG43', 'LG49', 'LG15', 'LG7', 'LFS3', 'LG32', 'LG18', 'LG3', 'LTS4', 'LG21', 'LFS3', 'LG18', 'LG15', 'LG4', 'LG27', 'LG43', 'LG24', 'LG11', 'LG47', 'LG49', 'LG38', 'LG44', 'LG48', 'LG45', 'LPS1', 'LG61', 'LG22' ... % slow swoop
    };

info.R1177M.badchan.epileptic = {'LG13', 'LG14', 'LG51', 'LG60', 'LPS2', 'LPI2', 'LPI3', 'LG23', 'LG24', ... % Session 2. Strong candidates for removal.
    'LG36', 'LG37', 'LG43', 'LG44', ... % Session 2. Minor, could be kept in, but definitely do track IEDs
    'LTS2', 'LTS3', 'LTS4'}; % Session 2, little spikes 

% Kahana 

% Line Spectra Info:
info.R1177M.FR1.bsfilt.peak      = [60, 120, 180, 200, 240, ...
    72, 216]; % Session 2 only
info.R1177M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5, ...
    0.5, 0.5];

% Bad Segment Info:
% 65/283 - 0.22968 13/47 - 0.2766

info.R1177M.FR1.session(1).badsegment = [152347,152600;178462,178969;240359,240793;278301,279771;328663,328858;560150,560669;698397,699142;699663,701253;926005,926312;996258,996783;1014577,1014983;1044420,1044624;1070387,1071084;1075073,1075338;1100377,1101414;1127038,1127338;1129109,1129253;1148027,1148396;1167705,1167892;1172001,1172453;1245891,1246163;1326001,1326201;1340395,1341265;1416192,1416818;1443361,1443591;1452001,1452201;1632524,1633360;1635826,1636000;1636982,1637263;1748702,1748926;1756182,1756457];
info.R1177M.FR1.session(2).badsegment = [341484,341876;342780,343473;349933,350380;352212,352644;354903,356000;359669,360540;365556,365769;366833,368163;371631,372000;382033,383638;391494,391876;393139,393462;394061,394707;400001,400471;402248,404000;420001,421561;423605,423930;424248,424483;425202,425497;428535,430000;431816,432155;432875,433150;436085,436481;437969,438247;439917,440149;444379,445098;446746,447003;449468,449888;461058,461380;467742,468000;468694,469150;470728,471886;472454,472741;474599,474882;476972,477223;482472,482711;486001,487166;487719,487964;488134,490000;490700,491329;492668,493207;493901,494253;495586,496000;499474,499815;502343,502578;505413,505763;522734,523005;523951,524141;533530,534691;540152,540348;542001,542582;545768,546000;578476,578634;587103,587356;593770,594000;596607,597053;600049,600435;604148,604586;622402,623267;626603,626850;627570,628000;628432,628767;631373,631646;654871,655074;656917,657084;662853,663158;668833,669251;670053,670951;684631,686000;688001,690000;692299,692729;697609,697797;721848,722000;722595,723839;724859,725620;730252,731857;733905,734000;755141,756638;757766,758000;775083,775366;784778,785096;789899,790354;792313,792677;793046,794000;795347,795543;796839,797132;811744,811936;812549,812906;843332,843692];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1136N %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Session 1 has massive buzz across channels that is not re-reref out; majorly affects baseline 1/f (very noisy instead of smooth).
% Only using Session 2. Session 2 has wide line noise peaks, but removeable. 
% LTL-occipital seizure onset zone.
% Session 2 is very clean, almost no fullblown, multi-channel IEDs. Removed a few events that were much more focal. 

% Channel Info:
info.R1136N.badchan.broken = { ... % 'G32', 'LF6', 'P3', 'RAD3', 'RALT6', 'RPHD4', 'RS2', ...  % antenna and breaks (Session 1)
    'RAD1', 'RAD2', 'RAD4', 'RALT2', 'LF5', 'LAST4', 'LF1', 'G29', 'G2', 'G32', 'RAD3', 'RS2', ... % antenna and breaks (Session 2)
    'RALT6'}; % late break
info.R1136N.badchan.epileptic = {'TT1', 'TT2', 'G4', 'G5', 'G7'}; 

% Kahana 

% Line Spectra Info:
info.R1136N.FR1.bsfilt.peak      = [60, 120, 180, 240];
info.R1136N.FR1.bsfilt.halfbandw = [0.8, 0.5, 1, 0.5];

% Bad Segment Info:
info.R1136N.FR1.session(1).badsegment = [1,3222000];
info.R1136N.FR1.session(2).badsegment = [1276178,1276631;1292158,1293381;1308001,1308252;1344602,1345691;1399883,1400333;1434791,1436000;1491730,1492000;1504001,1504312;1512352,1513590;1517327,1517606;1558549,1558771;1563073,1563723;1572646,1573248;1684271,1684824;1709622,1710118;1719407,1721320;1872154,1873244;1877662,1878328;2029577,2030771;2106327,2107888;2120723,2122393;2254525,2255384;2263786,2264000;2350762,2352000;2496489,2497300;2509646,2509804;2528001,2528429;2592888,2594038;2657936,2659243;2660880,2661320;2684920,2685671;2713110,2714832;2800529,2800663;2828920,2830219;2890500,2891296;2939794,2939977;2982650,2983957;2986097,2986759;3016658,3018207;3075024,3076000;3088888,3089409;3198714,3199521;3243798,3244191;3251762,3253026;3259754,3261506;3264908,3267937;3316529,3317058;3318432,3318695;3368082,3369788;3436989,3437477;3460747,3462844;3500457,3502824;3507258,3507908;3513992,3514312;3526121,3527695;3560372,3561397;3593416,3594485;3595311,3596292];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1127P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: 

% Channel Info:
info.R1127P.badchan.broken = {};

% info.R1127P.badchan.epileptic = {'LAT*', 'RP1', 'RP2', 'RP5', 'LPT*'}; % 'RPF1', 'RPF2' a little questionable
info.R1127P.badchan.epileptic = {'LAT1', 'LAT2', 'LAT4', 'RP1', 'RP2', 'RP5', 'RPF1', 'LAT3', 'LPT*'}; 
% LAT4, LPT3, LPT4, RP1 are LTL

% Not present in info.R1127P.allchan.label
% info.R1127P.badchan.kahana = {'RGRID20', 'RGRID21', 'RGRID22', 'RGRID28', 'RGRID29', 'RGRID30', 'RGRID34', 'RGRID35', 'RGRID36', 'RGRID37', ...
%     'RGRID38', 'RGRID40', 'RGRID41', 'RGRID42', 'RGRID43', 'RGRID44', 'RO2', 'RO3', 'RO4', 'RO5', 'RO6', 'RPST1', 'RPST2', 'RPST3', 'RPST4'};

% Kahana 

% Line Spectra Info:
info.R1127P.FR1.bsfilt.peak      = [60, 80, 120, 125, 172.2, 180, 200, 240];
info.R1127P.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
% cleaned until 259
info.R1127P.FR1.session(1).badsegment = [97703,98650;101705,102608;104176,105207;116724,116953;122778,123936;157165,158000;171697,172495;181189,182497;198063,198745;201056,201726;202119,202328;203391,204000;208607,209452;211421,211851;228738,229531;235846,236529;250436,250939;257576,258872;264154,265237;284111,284666;302387,303053;354242,355186;364468,365327;384291,385366;387842,388000;412635,413861;433012,433956;434001,435382;470716,471593;472194,473732;515431,516830];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1121M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: 

% Channel Info:
info.R1121M.badchan.broken = {};

info.R1121M.badchan.epileptic = {}; 

% Kahana 

% Line Spectra Info:
info.R1121M.FR1.bsfilt.peak      = [];
info.R1121M.FR1.bsfilt.halfbandw = [];

% Bad Segment Info:
info.R1121M.FR1.session(1).badsegment = [];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1112M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Lots of RTG (ltl) channels have the inverted, swoop-spike pattern
% Lots of small IEDs in addition to more prominent ones, and some channels have random one-off IEDs (kept these channels in)
% RSS2 acts up segment 510; RPS2-3 segment 557
% Much quieter IED wise in Session 2; more buzz episodes though
% A ton more large IEDs in Session 3; RMD starts blipping constantly
% Session 3 is near constant IED and has accuracy around 6%. Go figure.

% Channel Info:
info.R1112M.badchan.broken = {'RIF1', 'RIF2'}; % big swoops in Session 3

info.R1112M.badchan.epileptic = {'RMS*', 'RAS*', ...
    'RPS*', 'RTG20', 'RTG6', ...
    'RSS2', 'RSS3', 'RTG1', 'RTG13', 'RTG14', 'RTG7', 'RTG8'}; % big IED Session 2

% Kahana 'RAD1'    'RAD2'    'RAS1'    'RAS2'    'RMD1'    'RMD2'    'RMD3'    'RPD1'    'RPD2'

% Line Spectra Info:
info.R1112M.FR1.bsfilt.peak      = [60, 119.9, 180, 200, 239.7, ...
    69.9, 80]; % from last session
info.R1112M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.7, 0.5, 0.5, ...
    0.5, 0.5];

% Bad Segment Info:
% 27/202 + 26/150 + 3/37 

info.R1112M.FR1.session(1).badsegment = [100825,101676;120645,120763;125427,125561;131447,131765;133034,133325;139256,140092;141024,141825;143768,144000;173123,173593;175014,175370;179167,179557;201304,201388;215643,215805;275992,276535;280381,280832;281248,281559;301732,302374;310736,310842;329357,329710;353119,354000;368567,369122;369478,369801;381389,381549;403242,403368;423794,424000;463117,463710;467046,467638;473250,473575;475258,475604;486482,486769;503476,503755;512373,512697;526325,527283;556956,557176;558649,559029;559200,559432;563284,563716;577197,577845;578722,579323;593103,593362;593528,593765;594142,594465;594796,595033;595725,596000;613588,613888;622752,623454;631558,631823;636956,637331;642456,642906;645482,645799;646686,647124;651159,651543;652001,652292;683377,683618;694164,694463;698702,699082;730738,730916;732841,733666;737278,737539;780059,780324;784871,787720;809887,810253;815403,815718;829665,830292;842001,842826;844829,845102;846813,847229;852025,852858;896001,896189;915054,915654;930258,930546;938408,938759;947693,948000;948801,949061;954678,955074;967782,968000;978611,979660;997798,998000;1018001,1018265;1034905,1035144;1040343,1040540;1057097,1057553;1067772,1068000;1087832,1088000;1112001,1112263;1116676,1117033;1166807,1170332;1171524,1172783;1178905,1179112;1180001,1180274;1211683,1212000;1213633,1213857;1216619,1217162;1249681,1249944;1298271,1298467;1310220,1310433;1316742,1317674;1354448,1354626;1359191,1359696;1360234,1360854;1367885,1368267;1371292,1371519;1373907,1374090;1417590,1418000;1421637,1421851;1428001,1428374;1430121,1430497;1455399,1455686;1456710,1457055;1458766,1458926;1471774,1472689;1473645,1474110;1477705,1478000;1500190,1500570;1501598,1501968;1506720,1506983;1550704,1551090;1554321,1554455;1561091,1561912;1568807,1569005;1587885,1588320;1600875,1601315];
info.R1112M.FR1.session(2).badsegment = [86194,87126;88948,89269;118561,119184;132073,133718;157695,158654;164395,167049;184889,185279;185409,186274;188410,188715;190520,192602;193615,194000;220001,222390;230805,231489;232539,233088;256657,257410;258607,258957;267034,268223;273183,274594;281399,281819;282528,282832;284001,285285;288351,289749;297794,298991;316001,316963;320180,321307;322001,322858;326903,328000;336089,336316;336726,338000;339707,340265;341163,342795;356585,356789;358426,358828;369925,370167;381137,381541;383754,385676;387359,388000;397328,397972;398442,399319;400919,401229;402867,403364;411580,412366;413075,413797;418301,418739;435889,436096;442105,443366;453246,453612;455302,455632;460001,460467;463089,463346;469062,469505;474621,475865;478264,478842;486579,486993;502956,503110;512817,513656;525177,525477;531778,531930;536152,537666;548670,548797;552353,552866;567097,567938;568825,570000;593008,593277;608720,609726;611506,611896;616402,616935;623034,624779;639560,639853;664200,664521;669592,670300;696571,698259;702001,702646;704381,704848;709288,709773;713673,714491;740049,740697;756950,757333;761574,762265;781389,782000;783657,783926;808794,810151;818923,819291;828393,829166;842287,843223;860001,861541;885030,885152;894736,895547;907165,907616;911472,911853;917085,917331;918001,918390;923038,923338;937183,938000;949125,950795];
info.R1112M.FR1.session(3).badsegment = [268998,269100;274001,274916;278486,278997;281558,282000;282817,283475;287228,287493;288923,289134;291107,292000;292956,293331;300305,300626;301770,302000;302397,305013;306001,306799;308001,309743;314520,314874;315490,316000;320325,320511;321891,322000;324923,325323;326601,330000;330188,335646;336001,336459;337903,338000;338591,339755;342232,343378;345260,345861;346931,347017;347673,348000;348778,348985;350001,350737;352001,352451;353711,353819;356291,356509;368704,370000;370575,371043;373326,373599;374357,374523;375482,376000;376782,377648;379453,379702;380367,380624;384408,384673;385572,386000;387514,387718;388001,388533;390262,390947;391758,391960;392772,393166;394001,394330;394809,394932;395657,396000;396313,397223;398212,399843;400001,402000;402095,403751;404686,404804;405945,407471;409270,409388;410772,411372;412156,412429;413468,413745;414514,415182;416488,419565;420428,421251;422178,426000;426575,429868;430289,431620;432001,432816;434001,434376;434841,435489;438762,439628;440369,442000;442216,443801;447800,448000;448472,448709;449639,449805;450873,451797;452001,452074;453405,454000;454166,454437;455016,455309;456815,458562;462831,463074;466607,466908;468391,468485;469345,471114;474317,474749;476970,477130;478210,478290;481435,481722;496206,496290;497679,498354;498694,498822;502833,503078;505409,505745;508984,509231;509864,510000;513046,513346;513381,514519;523933,524000;526442,526759;528496,528804;533294,533720;537359,537446;538430,538743;541036,543120;544001,544852;547157,547555;549746,550000;551856,552000;552873,553547;554672,554848;556512,557321;560031,560324;561139,562000;562722,562820;564444,565974;566001,566904;567621,567708;568123,571579;572001,574000;575570,576000;577006,577694;578690,581839;582001,585648;587246,587442;592919,593430;597345,597861;599681,599821;600589,601128;602879,603307;604881,605851;606258,606681;607901,608000;609492,609777;613292,613523;618001,620000;620192,621315;622811,623055;624252,624405;629723,630000;630543,633654;634001,636711;637437,637561;638337,638415;639578,639664;640196,640566;643385,643644;653030,653396;655717,655950;656001,657201;657494,657569;661748,662000;663002,663535;668357,668691;677423,677555;678305,678382;679391,679646;681270,685743;686001,689428;711326,711535;712442,712610;713453,713684;717689,718000;719105,719428;722877,723017;725324,725567;726097,727817;730273,731309;736093,738000;739113,739307;740019,740306;741004,741255;742001,742675;742827,745444;746001,748000;748591,748834;749518,750000;754837,755051;759786,760000;762958,763410;766001,766106;768464,770000;770496,770757;771570,771801;774921,775434;778903,779720;789538,790265;792009,792288;793099,793338;794978,795112;796256,796515;797395,798000;799296,801414;804472,805180;809310,809382;809879,810191;811788,811922;834917,835122;837877,839029;842569,842707;844688,844840;852140,853567;853580,853704;854389,854830;855514,858000;858246,862000;862615,863956;864001,865505;866238,866546;867746,868000;868248,870000;871649,874000;879738,879878;881377,881775;882402,884425;886168,886846;890905,892292;894740,894880;895683,895880;896599,896818;897556,897916;898537,898683;904410,906560;907715,909201;910001,913126;913826,915920;916744,918000;919284,919599;920321,921211;922303,923410;924174,924350;925385,925571;926109,926342;927099,927658;928119,928290;928845,928989;929802,930000;932001,934000;934514,935311;936230,939225;940655,941269;944674,945440;949570,949696;951147,951305;952573,957537;959117,959882;963222,964000;973115,977281;980857,982890;983282,984000;984720,985406;986001,987573;988694,989672;1012788,1014000;1016113,1016257;1023907,1024000;1026001,1028000;1028462,1028654;1030543,1032000;1033405,1033610;1034549,1035348;1035796,1036000;1036585,1037275;1037770,1037872;1038007,1038241;1039137,1039390;1040001,1040679;1042792,1044000;1044936,1047622;1048001,1048679;1051306,1051952;1052768,1054000;1055369,1056000;1056313,1056610;1057163,1057491;1058005,1060000;1061536,1065283;1066071,1068965;1071012,1072000;1072897,1073878;1077246,1077327;1078508,1078580;1082001,1082340;1084746,1084983;1088091,1088197;1088514,1088860;1090944,1091819;1099290,1102000;1104845,1105096;1105864,1107809;1115286,1119348;1120001,1122000;1122301,1123086;1131071,1132000;1133478,1135624;1136001,1139912;1140001,1143910;1144105,1144360;1145224,1147622;1148001,1152000;1152458,1155597;1156140,1156457;1157903,1158459;1160293,1161011;1174940,1175319;1178170,1182000;1182686,1182870;1190343,1190556;1193820,1194000;1204252,1204352;1207572,1209569;1210476,1210652;1212311,1213049;1214927,1215777;1217220,1217327;1225647,1225849;1229117,1229751;1230218,1230257;1231294,1232074;1237183,1237404;1247266,1248632;1249560,1250000;1250821,1251464;1254063,1254302;1255214,1255376;1266506,1268000;1270321,1270638;1272454,1272864;1276297,1278000;1286001,1288000;1293123,1293577;1294583,1298000;1298446,1300864;1302001,1302570;1303854,1304000;1304190,1304348;1305766,1306000;1306371,1306781;1307711,1307851;1308351,1309303;1312510,1312836;1319780,1320882;1321455,1322000;1322194,1322467;1327790,1328495;1331026,1331378;1332502,1332697;1332847,1336000;1336166,1336251;1337085,1337192;1338067,1340000;1341596,1344000;1344309,1347170;1348001,1352000;1357683,1357819;1360992,1361094;1362625,1362727;1372827,1373505;1374269,1375106;1381413,1382000;1385762,1386000;1386605,1387096;1387387,1387638;1390829,1390910;1393165,1393277;1396716,1396824;1400305,1402880;1404516,1404908;1405528,1406675;1407746,1408000;1408389,1409682;1411191,1411293;1412383,1413138;1418216,1418390;1420359,1420459;1437671,1437878;1441550,1441646;1446547,1446677;1459193,1459446;1460136,1460298;1469715,1470000;1477312,1478000;1479393,1480000;1481270,1481507;1482440,1482610;1483421,1483585];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1102P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Massively bad reference noise at the beginning and end of the session. Trials are all located in the cleaner middle.
% Some widespread IEDs, some of them very small and subtle. 
% Everything is very ambiguous.
% Too many temporal channels removed.

% IED at segment 453
% segment 521
% segment 544
% 732

% Channel Info:
info.R1102P.badchan.broken = {'ROF5', 'LAT3'}; % starts slowly swooping

info.R1102P.badchan.epileptic = {'RAT1', 'RAT2', 'RAT3', 'LPT2', 'LPT3', 'LPT4', 'RMT*', ... % segment 453
    'RAT4', 'ROF1', 'ROF2', 'RPT3', 'RPT4', ... % 521
    'LAT1', 'LAT2', 'LAT3', ... % 544
    'LMT*' ... % 732
    }; %'RPT*', 'RAT*', 'RMT*', 'LPT*', 'LAT*', 'LMT*', 'ROF*'}; % seem to regularly inverse discharging; cannot mark them all 

% RMT, RAT, LMT, LAT, LPT, RPT confirmed; subject not salvageable 

% Kahana 'LDH2'

% Line Spectra Info:
info.R1102P.FR1.bsfilt.peak      = [60, 80, 120, 160, 180, 200, 240];
info.R1102P.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]; 

% Bad Segment Info:
% artifacts marked until segment 778
info.R1102P.FR1.session(1).badsegment = [1,785871;790001,791003;802001,802316;803685,804453;816676,816860;823784,824138;829891,830558;834974,835632;840001,840261;868105,868447;873280,873557;880964,881368;891278,891551;893121,893454;896341,896689;903463,904000;904698,905876;907478,907678;909784,909946;920307,921086;924365,924842;925514,925757;932524,932846;943256,943499;943800,944100;972732,973333;997782,998070;999784,1000116;1021332,1021565;1040369,1041344;1068472,1069047;1084341,1084930;1086303,1086723;1109760,1111724;1123137,1123587;1146655,1147839;1167367,1168725;1228633,1229100;1240037,1241656;1245824,1246259;1251371,1253178;1268569,1270191;1282504,1282969;1287681,1287962;1290404,1292731;1324897,1325299;1337528,1337837;1356001,1356916;1376395,1376729;1390931,1391271;1403288,1403952;1406931,1407301;1408134,1408344;1421752,1422669;1439107,1439382;1442051,1442461;1447195,1447543;1451264,1452372;1462418,1463797;1473349,1473662;1494260,1494529;1502325,1502783;1508803,1509386;1512426,1513247;1514905,1515305;1524387,1524677;1527669,1528185;1533147,1533477;1534726,1535741;1554198,1554437;1554982,1556000;2059936,2116058];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1089P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Strong reference noise, but re-referencing removes it almost completely.
% IEDs are relatively infrequent, but appear across many, many electrodes.
% Removed IED electrodes, including those that appear synchronous with them.
% Slow swoops across multiple channels. Marked these trials, did not remove channels.
% Overall, not a clean subject. IEDs across many channels. Ambiguous events remaining.

% segments 158 - 765
% First IED at segment 215
% Big ied at segment 240
% Segment 501

% Channel Info:
info.R1089P.badchan.broken = {'RG56', 'RG51'}; % big antenna event early; big swoop

info.R1089P.badchan.epileptic = {'RG10', 'RG11', 'RG12', 'RG13', 'RG14', 'RG20', 'RG21', 'RG22', ... % segment 215
    'RAT1', 'RAT2', 'RG15', 'RG16', 'RG17', 'RG18', 'RG19', 'RG2', 'RG3', 'RG4', 'RG9', 'RG25', 'RG26', 'RG27', 'RG28', 'RG29', 'RG30', 'RG31', 'RG46', 'RG47', 'RG48', 'ROF4', 'ROF5', 'ROF6', 'RTO3', 'RTO4', ... % segment 240
    'RAT3', 'RMT*'}; % segment 501

% Initial cleaning. Re-did to see if some channels could be kept.
% info.R1089P.badchan.epileptic = {'RG1', 'RG2', 'RG3', 'RG4', 'RG9', 'RG10', 'RG11', 'RG12', 'RG13', 'RG14', 'RG17', 'RG18', 'RG19', 'RG20', 'RG21', 'RG22', 'RG25', 'RG26', 'RG27', 'RG28', 'RG29', 'RTO1', 'RTO2', 'RTO3', 'RTO4', ... % IEDs
%     'RAT*', 'LAT*', 'RMT*', 'ROF*', ...
%     'RG15', 'RG16', 'RG23', 'RG24', 'RG30', 'RG31', 'RG46', 'RG47', 'RG48'};

% Kahana 'RDH1'    'RDH2'    'RDH3'    'RDH4'    'RG5'    'RG6'    'RG7'    'RG8'    'RPT1'    'RPT2'    'RPT3'    'RPT4' 'RTO5'    'RTO6'

% Line Spectra Info:
info.R1089P.FR1.bsfilt.peak      = [60, 75, 80, 120, 125, 175, 180, 200, 240];    % confirmed
info.R1089P.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]; % confirmed

% Bad Segment Info:
info.R1089P.FR1.session(1).badsegment = [315038,315634;330228,330568;333516,333821;343679,344000;351036,351323;359439,359732;363280,363503;364885,365265;365944,366458;369052,370000;370651,371829;372869,373152;377695,378388;380142,380832;388625,388856;389516,389678;392194,392396;402436,402725;411568,411797;411896,412888;413627,414000;417288,417505;424543,425158;428925,429336;430404,430840;433621,433845;444734,444991;446895,446949;452668,452937;457520,457801;461488,461908;462651,463001;463540,464572;465018,465305;465838,466427;475860,476314;477663,477841;479165,479710;485824,486120;486569,486781;487262,487698;501631,501888;505596,506068;509252,510076;511766,512000;512690,513414;515848,516062;533871,534000;542454,542789;549322,549551;554893,555110;562182,562586;564119,564322;565560,565843;569008,569269;569895,570106;571619,571868;574611,574947;591200,591412;600125,600342;604670,604884;609498,609726;614510,614868;616700,617196;620605,620937;626579,626854;630134,630479;642827,643162;653862,654094;655937,656175;659564,659755;660045,661015;667929,668217;672055,672263;675784,676000;683500,684267;701328,701948;703578,703849;709552,710000;720001,720336;720782,721007;723232,723557;739054,739295;746944,747160;748718,749023;749532,749811;754460,754715;764807,765063;775288,775537;775850,776465;781748,782000;786001,786276;798468,798729;807095,807690;812307,812804;814230,814550;818803,818979;834645,835076;836158,836382;836796,837245;847042,847557;852512,852928;855306,855801;865699,866000;880359,880755;894938,895775;900649,900870;906262,906747;908984,909553;916903,917174;942555,942834;950923,951333;953008,953456;954266,954505;958530,958814;960702,961380;970599,971313;998968,999317;1001371,1001843;1002879,1003104;1007131,1007410;1013365,1013622;1014146,1014439;1020125,1020328;1046319,1046707;1062194,1062628;1070524,1070957;1083671,1083890;1101073,1101333;1103738,1103954;1104845,1105694;1111216,1112795;1123701,1123948;1125778,1126000;1141812,1142000;1145020,1145575;1159592,1160000;1160381,1160572;1167177,1167362;1180303,1180564;1192406,1192918;1194962,1195243;1202391,1203340;1236863,1237114;1240688,1241007;1248573,1248834;1251266,1251992;1252393,1252701;1259337,1259652;1281897,1282496;1286573,1286868;1296140,1296523;1300690,1301084;1313679,1313910;1314585,1315015;1325830,1326312;1361667,1361930;1370847,1371741;1373932,1374332;1393665,1394165;1397637,1398000;1398474,1399422;1400254,1400671;1405332,1405724;1416262,1416491;1433590,1433827;1440001,1440310;1441089,1441624;1445238,1445521;1446001,1446251;1446974,1447406;1455772,1456527;1457895,1458149;1463623,1463853;1486001,1486671;1495760,1496122;1496305,1496493;1507137,1507370;1508422,1508888];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1086M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: IEDs across many channels, remving a few at the core

% Channel Info:
info.R1086M.badchan.broken = {'LIOF8', 'LPTD1'};

info.R1086M.badchan.epileptic = {'LAS2', 'LMS1', 'LIT9' ... % 40
    }; % , 'LST9', 'LIT2', , 'LAS4'

% Line Spectra Info:
info.R1086M.FR1.bsfilt.peak      = [60, 79.9, 120, 180, 200, 240];
info.R1086M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.6, 0.5, 0.5];

% Bad Segment Info:
info.R1086M.FR1.session(1).badsegment = [79310,79737;81703,82000;83016,83297;86001,86247;89934,91116;92292,92914;101889,102687;105058,105268;106064,106664;109149,109523;111909,112291;121645,122233;125025,125309;130793,131156;134986,136296;141734,142140;142917,143439;144229,144552;153006,153212;157279,157462;159523,159783;163046,163589;174914,175154;177944,178164;179005,179665;180752,180992;182976,183316;186331,186515;188872,189212;192709,192816;200823,201328;212238,212333;212822,213102;216268,216526;219187,219505;221471,221985;224550,224779;226910,227014;229208,229343;234216,234502;237338,237513;237923,237993;248288,248434;250357,250626;254712,254872;255290,255536;259084,259384;272432,272635;274262,275857;280312,280615;285448,285628;289292,290011;294882,295587;296757,296940;297099,297346;299637,300257;307234,307418;307429,307668;313909,314146;321825,322310;322946,323109;329422,329640;329663,329926;335144,335208;335950,336171;336980,337206;339021,339230;339663,339889;340361,340601;341196,341388;342068,342188;343158,343375;345470,345713;352197,352532;352565,352802;359915,360252;363219,363368;364755,365238;370551,370803;373274,373396;379155,379324;383784,384107;387847,388224;388230,388685;396206,396675;399246,399458;401365,401644;404704,404984;409495,409784;410805,410999;413481,413588;415328,415549;416218,416439;425261,425484;426623,426824;435744,436297;436674,436878;439142,439410;447788,448051;453381,453639;454792,454975;455491,455723;456526,456752;463806,464000;465907,466620;469594,469799;477933,479416;480821,480990;487323,487552;492073,492792;495702,495987;501246,501869;508883,509040;509787,510090;513465,513674;518499,518859;526599,526725;526734,526876;528058,528375;538273,538681;540884,541230;542135,542333;544886,545175;547386,547607;551629,551912;557050,557277;562929,563130;563137,563366;565718,565998;573254,573455;574766,575152;577098,577256;587440,587965;596175,596367;600910,601074;601085,601446;602821,603118;608078,608312;616099,616357;616679,616956;618001,618167;623740,624157;626562,627341;628714,629334;630501,630644;631739,631971;634690,634921;635602,635822;641300,641586;642068,642277;646366,646573;649149,649737;651692,652263;654625,654874;656835,657050;659016,659439;661125,661354;662613,662791;665327,665488;666915,667015;672873,673064;674102,674305;675154,675311;685859,686407;688749,688995;691814,692328;693603,693966;695766,696265;709699,709828;709844,709936;712431,712571;715369,715479;719496,719660;722881,723011;723026,723241;726158,726340;727064,727223;727248,727299;728597,728820;732712,732930;732944,733029;739935,740000;740007,740038;741040,741469;742518,742793;750037,750221;750240,750328;753905,754052;761177,761321;764301,764489;766645,766840;766861,767126;769790,769976;774391,774574;776166,777438;779427,779489;779522,779708;781711,781900;782182,782384;785139,785221;785238,785315;789871,790554;790579,790664;793228,793374;793895,793974;794484,794630;802478,802648;810001,810199;810214,810304;811970,812139;815774,815986;826365,826527;828079,828298;830123,830316;830547,830677;831433,831648;838541,838892;838905,839650;842696,842797;842815,843352;849226,849394;852053,852187;852198,852525;858069,858229;858238,858735;861552,861638;864518,864636;864653,865114;868496,868652;868659,869142;871099,871650;872323,872403;872436,872489;873780,873930;873935,874000;880009,880270;880287,880731;884230,884314;884917,885567;887067,887154;887173,887213;889895,890000;890492,890735;892246,892413;900567,900816;907107,907194;923427,923666;929850,930413;933407,933450;933476,933543;943806,943896;943911,944000;948563,948973];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1069M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Very clean.

% Channel Info:
info.R1069M.badchan.broken = {'LFGP49', 'LFMS4', 'LFIS1'}; % not massive breaks, but big slow drifts

info.R1069M.badchan.epileptic = {'LIS3', 'LMS1', 'LMS2' ... % 304
    };

% Line Spectra Info:
info.R1069M.FR1.bsfilt.peak      = [60, 120, 180, 200, 240];
info.R1069M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1069M.FR1.session(1).badsegment = [175609,177996;234649,234872;274065,274282;376611,376924;407780,407916;464968,465070;571393,571847;607204,607543;623306,623622;662958,663136;705163,705301;727778,728000;732335,732574;737744,737868;742776,743041;787693,788187;832593,832864;854001,858000;926146,926326;980293,980564;1091629,1091831;1107881,1108773;1136897,1137271;1201429,1201515;1237353,1237694;1273236,1273442;1280708,1280932;1312577,1312868;1345530,1345902;1359683,1360120;1419492,1419926;1423326,1423513;1449542,1450894;1460577,1460854;1466579,1466773;1480369,1481013];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1067P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Lots of IEDs

% Channel Info:
info.R1067P.badchan.broken = {'LG56', 'RA4'};

info.R1067P.badchan.epileptic = {'LG49', 'LG50', 'LFP8', ... % little spikes
    'LMT1', 'LMT2', 'LPT1', 'LPT2', ... % IED
    'LAT3', 'LAT4', 'LG33', 'LG34', 'LG35', 'LG36', 'LG51', 'LG52', 'LG57', 'LG58', 'LG59', ... % 150
    'LMT3', 'LMT4', 'LG45', 'LPT3', 'LPT4', ... % 198
    'LAT1' % session 3 184
    }; 

% Line Spectra Info:
info.R1067P.FR1.bsfilt.peak      = [60, 80.1, 120, 159.9, 179.9, 200, 213.2, 220, 230.4, 239.9];
info.R1067P.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.7, 0.5, 0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
% 12/93, 16/182, 40/161
info.R1067P.FR1.session(1).badsegment = [272115,272638;275359,275874;279546,279650;280347,280610;280621,280715;283403,283722;299181,299460;300220,300481;302174,302439;305093,305221;320269,320586;327800,328157;329766,330000;332220,332429;341274,341690;342408,343029;346694,346989;349586,349847;351230,352000;352129,352542;365788,366135;378194,378384;380035,380344;385482,385604;386146,386328;388103,388523;393109,393253;394831,395146;402663,403575;403794,403964;404222,404467;405840,406078;407665,408388;415004,415263;432617,432928;436242,436423;437375,437698;441119,441485;447976,448293;454440,454656;456091,457184;467810,468000;474927,475086;475097,475203;475208,475319;476798,477003;479087,479515;485351,486586;487206,489741;497727,498000;499365,499543;500720,500961;501663,501767;501774,501930;512119,512274;513296,513515;535558,536207;542166,542409;547613,547843;548146,548253;548595,548818;551242,551400;552085,552419;558214,558394;559183,559602;566001,566257;586001,586286;590273,590479;593371,593458;604496,604656;615782,616000;625365,625666;633506,633684;642001,642169;654307,654507;656524,656900;659738,660000;671637,672739;692807,693211;698561,698874;707415,707604;720887,721686;722974,723376;733687,734000;740700,741070;742571,743025;744156,744463;749079,749404;756827,756906;769294,769452;773649,774000;786216,786362;788277,788467;790629,791078;791955,792221;793613,793823;809560,809831;812299,812513;817064,817569;822001,822302;830849,830953;838788,839043;840927,841243;846001,846592;854970,855545;858073,858358;861601,861978;864813,865257;868724,869414;870938,871340;873230,873493;876760,877144;880647,880888;880946,884409;886097,886445;902420,902618;913314,913660;914555,915084;917455,917670;932754,933158;942891,943235;949399,949831;954750,955462;955504,955676;956676,956953;958726,958914;962857,963112;965864,966000;981220,981416;984448,985072];
info.R1067P.FR1.session(2).badsegment = [303195,303495;304758,304862;306184,306255;310992,311527;327528,327747;337834,338000;344464,345783;351415,351523;358103,358753;362702,362767;364593,364928;366893,367479;370160,370415;371381,371436;387443,387678;402569,403704;407443,407662;408242,408382;416059,416112;417349,417473;418631,418745;421292,422000;422659,422924;441492,442000;443508,443696;446170,448000;450093,450409;456234,456683;464623,464824;465439,465759;468881,469305;471048,471481;477643,478000;483778,484491;500289,500425;503864,504000;508464,508870;524134,524421;524426,525164;527139,527666;541826,542112;543300,543523;543899,544824;546549,547158;547437,547942;548782,549009;561465,562000;566668,567628;570001,570461;575218,575521;577838,578344;579744,580332;581185,581819;598438,598683;601284,601541;601558,601906;609850,610000;620283,620850;623085,623285;647701,648507;657774,657950;659135,659432;659891,660167;661155,661442;662240,662922;676472,676578;683335,683654;690885,691283;691768,692000;692853,693029;695463,696000;702279,702425;713264,714000;730001,731452;752426,752789;758051,758159;765335,765485;766746,766977;773850,774745;774974,775041;778001,778205;791183,792000;792138,792322;797026,797277;798001,798074;799286,799505;801564,802294;802551,802769;805693,805942;806369,806586;811893,812000;817496,817569;824277,824382;825191,825329;831169,831464;832450,832765;835413,835743;841256,841527;842579,842993;843419,843793;847731,847922;861373,861718;866051,866356;874176,874485;876680,877483;890001,890538;892537,892806;899492,899622;904738,905597;911335,912342;917659,918763;924349,925323;933828,934000;936369,936640;946001,946308;947687,948548;951389,951491;961359,961708;970976,971569;979820,979968;995208,995249;996801,996939;998001,998120;1004837,1005188;1006976,1007553;1010408,1011082;1023175,1023255;1031439,1031680;1032805,1033795;1042234,1043267;1049635,1049767;1068575,1069279;1074182,1074394;1085824,1086000;1094484,1095221;1096343,1096806;1097419,1098000;1098595,1099581;1102204,1102808;1107280,1107394;1113520,1113652;1117030,1117164;1118998,1119186;1128001,1128683;1140522,1141648;1143776,1144000;1155232,1155726;1160387,1160630;1164293,1164479;1173016,1173253;1185064,1185180;1190001,1191055;1196639,1196753;1198079,1198263;1200778,1201753;1203425,1203602;1205705,1206205;1207187,1207581;1208940,1209158;1262001,1262959;1269304,1269539;1270001,1274000;1277768,1278000;1278877,1279551;1287218,1287344;1303711,1304000;1310919,1311285;1312968,1313549;1316117,1316374;1326001,1326328;1338001,1338795;1347447,1347696;1348778,1349223;1352958,1353567;1358784,1359458;1375844,1376000;1380905,1381340;1386807,1387313;1390262,1390527;1391419,1391710;1394001,1395591;1398001,1398614;1403929,1404155;1406478,1406987;1408885,1409708;1410313,1410376;1414402,1414515;1432454,1432666;1433423,1433507;1439387,1440558;1441554,1441722;1441772,1442000;1449828,1450749;1454371,1455684;1461895,1462000;1467391,1467491;1469699,1470415;1478637,1478723;1480444,1482743;1485433,1486000;1486238,1486844;1488055,1488169;1489389,1489640;1491850,1492679;1496877,1497730;1497860,1497948;1501550,1502000;1503425,1504000;1507881,1508197;1514194,1514306];
info.R1067P.FR1.session(3).badsegment = [417506,417894;425264,425402;427603,428000;428532,428749;430663,430979;433514,433771;443486,443803;443919,444441;454913,455182;457461,457686;460172,460396;460968,461207;464264,464481;471546,472000;472676,473049;475667,476000;477397,477525;478428,478876;480121,480310;493554,493698;494631,495430;495532,497126;499024,499225;499254,499773;500454,500612;502375,502816;502829,503007;503740,504000;504319,504405;506436,506548;519284,519545;520279,520715;522111,522503;524716,525269;528688,528894;531421,531656;532609,532858;533538,533839;536224,536527;537079,537269;537276,537557;538516,539759;549952,550403;553931,554356;556178,556358;559085,559525;560095,561132;564335,564427;573427,573686;576655,576997;579887,580185;585629,585690;587463,587946;590853,590977;594698,594949;597901,598000;601302,601503;607248,607551;611526,611563;616414,616733;626863,627152;627933,628356;636786,636908;639897,640000;642389,642556;644264,645279;646307,646461;660526,661211;661218,661426;668766,669039;681899,682000;685937,686076;690710,690848;700001,700991;706466,706666;707824,707962;712001,712235;713153,713537;713619,713849;717149,717255;719236,720000;726001,726118;728214,728570;731341,731700;734647,735348;735893,736000;739324,739676;748412,748636;748694,750000;751294,751487;756502,757043;758001,758515;763210,763338;764587,764977;771052,771160;772825,773027;776996,777136;778190,778380;779778,780000;786873,786999;791004,791595;795341,795489;797429,797692;806023,806122;810001,810461;812244,812773;818051,818673;824512,824757;825891,826130;829391,829632;841584,842187;851177,851464;855913,856225;860823,861293;861969,862179;862397,862572;876001,876973;879862,879922;891351,892679;893357,893491;898645,898922;902206,902529;904033,904263;908512,908761;910339,910741;912541,913017;932097,932292;940381,940574;941425,942000;942387,942787;947060,947428;948829,948979;953326,953505;960796,961005;961659,962000;967085,967217;967909,968318;975351,975726;982952,983678;990488,990721;991417,991670;996861,997094;998071,998723;1000129,1000471;1000974,1001460;1002881,1003696;1009395,1009751;1010446,1010719;1011266,1011906;1013038,1014116;1018228,1018763;1019326,1019442;1020001,1020910;1025347,1025662;1029901,1030278;1036055,1036270;1037806,1038000;1040857,1041136;1049091,1049686;1049893,1050000;1058865,1060000;1060801,1061247;1084897,1085702;1097468,1098000;1100500,1101718;1103768,1104642;1105498,1105678;1123145,1123499;1134486,1135545;1136476,1137662;1154863,1155148;1156778,1156900;1158001,1158320;1162952,1164000;1179097,1180165;1180615,1181114;1183220,1183440;1187435,1187908;1193588,1193785;1194001,1194237;1195627,1195851;1198262,1198753;1211044,1211289;1214422,1214979;1215655,1216000;1226889,1227209;1230001,1230495;1233508,1233732;1234369,1234548;1242347,1242656;1246629,1246932;1249607,1249863;1262198,1262290;1270446,1271295;1274119,1274181;1288327,1288497;1307393,1307648;1314537,1314638;1326077,1326894;1327691,1327868;1341705,1342000;1347385,1347825;1349574,1349920;1350549,1350878;1360138,1360362;1368539,1369755;1374363,1375400;1378349,1378628;1383802,1384000;1391562,1392965;1405879,1406310;1409598,1409732;1419316,1419430;1427615,1430000;1436230,1436429;1438260,1441938;1442393,1443076;1446121,1446378;1450663,1450846;1454224,1454445;1462960,1463122;1465101,1465390;1468954,1469104;1472329,1473595;1481447,1482000;1482313,1482461;1483087,1484314;1492690,1493011;1502113,1502396;1513935,1514403;1525852,1526640;1529867,1530392;1532387,1532731;1534138,1534642;1535891,1537158;1543500,1543676;1545701,1545898;1546113,1546838;1550385,1550679;1558649,1558858;1566545,1566753;1567917,1568296;1569778,1570000;1570436,1570926;1575931,1576368;1578001,1578278;1580678,1581515;1582541,1582908;1590796,1590876;1595496,1595962;1597588,1598000;1605264,1605475;1608001,1608536;1612206,1612463;1613794,1615076;1621322,1622000;1627161,1627384;1628543,1629027;1629441,1629654;1638111,1638548;1649572,1650415;1651306,1651702;1658424,1658693;1659856,1660068;1663135,1663426;1665707,1666000;1666772,1667065;1668262,1668979;1672510,1672767;1678665,1679047;1708420,1708795;1722722,1723948];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1066P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Lots of IEDs. Not sure I'm catching all of them.

% Channel Info:
info.R1066P.badchan.broken = {'RF5'};

info.R1066P.badchan.epileptic = {'LAT4', ...
    'LMT2', 'LMT3', 'LPT2', 'LPT3', 'LPT4', ... IED
    'LF6', ...
    'LPT1', ...
    'RPT*', ...
    'RMT2', 'RMT3', 'RMT4' ...
};

% Line Spectra Info:
info.R1066P.FR1.bsfilt.peak      = [60, 120, 125, 179.9, 200, 239.9, ...
    75, 80, 159.9, 174.9, 224.9];
info.R1066P.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.6, 0.5, 0.5, ...
    0.5, 0.5, 0.5, 0.5, 0.5];


% Bad Segment Info:
% 82/220, 32/94, 86/260, 86/225
info.R1066P.FR1.session(1).badsegment = [408166,408350;409208,409342;410204,410400;412827,412985;414758,415041;415615,415868;419736,419966;422954,423106;423328,423930;425149,425668;427482,427722;428333,428574;434204,434360;446196,447158;447911,448155;457637,458000;459603,459658;459663,459807;462001,462717;465067,465315;468809,469023;476813,476932;510480,510685;513314,513602;514478,514802;516440,516810;523389,524153;554601,554832;564001,564779;567117,567487;600083,600348;603514,604247;604283,604473;616478,617940;620762,622000;631633,631906;634127,635249;637933,638409;638994,639307;640762,640975;641405,641745;646581,646864;648758,649714;652839,653025;662794,663303;672524,672858;674097,674300;675310,675499;715776,715976;717145,717968;718192,718332;762670,763285;777906,778138;778301,778451;788087,788233;809826,810100;819133,819275;824327,824538;840649,841213;857085,857422;863183,863559;878794,879088;883050,883261;886927,888000;916702,918000;918647,918949;920188,920390;932001,932701;936158,936497;937451,937749;960760,960898;962001,962171;962670,962924;967169,967358;978131,978386;978680,979285;986905,987106;1001828,1002000;1009788,1009966;1021276,1021523;1053349,1053579;1061798,1061928;1066986,1067176;1082277,1082525;1085808,1086000;1092954,1093023;1102641,1102763;1103619,1103853;1123371,1123513;1126678,1126973;1130001,1130717;1131296,1131414;1152831,1152993;1154001,1154267;1166470,1166721;1181435,1181706;1191246,1191479;1196001,1197033;1200672,1200850;1219195,1220000;1223661,1224499;1246061,1246405;1248476,1248737;1254827,1255092;1268345,1268584;1268811,1269861;1278952,1279186;1295550,1295835;1301592,1301749;1302946,1303241;1306907,1307118;1315109,1315174;1326744,1327444;1339371,1339624;1345125,1345384;1358881,1359027;1372976,1373055;1384047,1384143;1392021,1392217;1400001,1400257;1405121,1405273;1416720,1416957;1423250,1423847;1428460,1428652;1468750,1469021;1490909,1491430;1493687,1493978;1527570,1527845;1535064,1536398;1536901,1537164;1539594,1540959;1542514,1542717;1597512,1597763;1617341,1617464;1627891,1628151;1631709,1632000;1637353,1637579;1658230,1659005;1659332,1659535;1660555,1660656;1662438,1662795;1665860,1666000;1676815,1678000;1681679,1682000;1683290,1683551;1684962,1685338;1687556,1688000;1688532,1688757;1689601,1689823;1694766,1694971;1699071,1699255;1699494,1699910;1702414,1703610;1727075,1727737;1738784,1739535;1748001,1748223;1764964,1765160;1791032,1791100;1792412,1792983;1816627,1816797;1820714,1820981;1844887,1845088;1846490,1846658;1846915,1847112;1850079,1850721;1853018,1854000;1855187,1855561;1860559,1861741;1864254,1864511;1869347,1870104;1874001,1874249;1878119,1878411];
info.R1066P.FR1.session(2).badsegment = [388954,389180;391474,391716;392805,393148;394055,394288;400545,400810;402353,402469;404001,404159;415266,415837;425461,425763;430702,431336;432001,432356;435830,436052;436629,436755;439393,439626;444001,444177;447792,448000;448575,449029;449060,449356;456395,456781;488480,488717;497472,498000;501818,502000;502091,502334;502629,503090;515453,515644;519330,519626;521109,521336;547792,547938;554337,554983;556770,557128;575792,576112;577268,577529;579494,579761;597490,597684;601629,601876;623244,623471;641042,641243;643181,643410;643617,643801;644127,644298;645598,645910;656925,657166;662555,662880;676331,676580;677127,677466;685508,685787;689312,689680;690252,690318;691004,691404;692089,692560;732807,732955;736780,736912;738520,739007;765892,766172;766843,767033;783032,783583;785022,785896;790001,790874;792325,792536;794101,794374;794796,794971;795393,795589;796057,796316;798524,798755;819427,819569;827558,827767;828091,828320;851649,851934;856752,856993;860001,860139;861379,861972;864786,865011;879657,880000;880988,881543;881883,882114;883159,883398;890661,890836;892037,892171;896619,896787;898269,898396;908718,909515;960837,961289;990936,991144;994962,995360;995681,996000;1004591,1004848;1008001,1008189;1011280,1011452;1020412,1020646;1039909,1040286;1050319,1050628;1051534,1051642;1054720,1055166;1058633,1058779;1059405,1060000;1067637,1067924];
info.R1066P.FR1.session(3).badsegment = [226837,227005;227439,227702;227794,228000;234865,235279;242113,242372;243750,244080;244849,245090;245330,245859;250807,251023;256170,256409;263411,263632;263816,264000;266730,267146;272670,272743;273532,273745;274694,275450;275798,275970;288333,288896;292264,292689;297278,297521;299558,300000;302611,302874;322647,323092;332514,332912;362905,363092;366291,366400;373520,373714;382551,382757;396635,396711;396726,397025;409427,409674;413129,413452;438158,439184;440766,441331;442152,443128;446714,447263;448649,448880;448895,449192;510095,510328;526069,526538;544917,545072;560101,560219;563502,563759;571423,571803;592127,592308;594661,594945;595810,596000;597278,597735;608978,609263;609719,610000;612923,613198;618287,618529;624134,624417;641101,641336;650891,651045;656101,656330;660071,660282;663671,663863;675526,675658;676589,676656;676670,676848;687210,687485;688180,688282;695361,695452;708001,708296;710462,710683;711042,711283;711927,712000;726297,726586;728416,728650;730710,731041;733903,734146;736202,736292;742059,742235;744035,744282;759524,759787;773341,773595;780307,780515;782264,782544;790522,791340;792001,792082;794001,794082;798952,799130;803734,804000;809627,809863;827756,828000;830152,830455;834772,835205;840661,841358;853889,854100;858772,859102;872162,872431;874127,874316;876260,876477;879151,879285;895391,895616;901407,901765;902524,903037;903079,903676;907284,911541;960655,961559;1046244,1046556;1081252,1081527;1126301,1126719;1170291,1170542;1288365,1288634;1446651,1447053;1525197,1525499;1526271,1526606;1546349,1546622;1562313,1562600;1571169,1571747;1622796,1623386;1624740,1625186;1636414,1636959;1642905,1643575;1673169,1673670];
info.R1066P.FR1.session(4).badsegment = [234001,234153;237453,237527;240061,240941;259661,259819;264156,264388;268365,269110;280059,280193;280801,281172;285119,285450;286134,286274;307062,307424;310635,310681;311151,311503;312254,312536;319012,319634;354593,354783;360865,361676;362218,362759;363480,363811;364001,364209;366774,366939;367274,367561;368176,368388;385335,386153;409103,410000;421155,421948;424087,424308;451492,451708;452283,452600;455113,455533;457403,457591;458929,459440;473248,473892;474549,474691;482001,482487;498418,498876;508506,508979;512127,513055;520077,520270;523457,523545;548232,548445;551822,552000;565355,565779;566001,566848;567052,567456;570001,570282;572144,572920;573729,574000;577659,578483;578559,578713;579032,579259;579302,580112;592069,592183;594516,594812;595566,595791;596001,596431;630631,632000;632289,632497;640964,641088;645073,649196;650001,651096;660202,661479;662637,663658;673586,673910;679153,679581;684944,685201;692053,692249;699133,699293;703020,704000;705869,706000;709528,709751;712774,712941;726359,726473;746861,747027;752345,752640;755159,755340;762657,762904;792982,793275;816553,816693;830841,831035;832025,832278;841405,841525;842778,843749;843796,843960;851320,851513;891455,891720;892960,893035;894520,894658;898176,898443;936001,936993;940071,940989;943413,943646;958037,958261;965746,965994;966001,967011;967633,967793;988091,988620;1002001,1002596;1056627,1057382;1058210,1058441;1147443,1148149;1154831,1155745;1168043,1168743;1194031,1195799;1197258,1197787;1200001,1200862;1315234,1316000;1339476,1342000;1361613,1362538;1405264,1405622;1405814,1406767;1411387,1414320;1414408,1416000;1455200,1456396;1504017,1508000;1564079,1567886;1634593,1635813;1648349,1648842;1751387,1752000;1762329,1762842;1762915,1763501;1778424,1778804;1787393,1787759];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1060M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Session 2 has major breakages across all channels. Found a shorter section within there that might be clean.
% Sessions 1 and 2 have IEDs, Session 3 only buzzy episodes
% Session 1 297 - big IED across multiple

% Channel Info:
info.R1060M.badchan.broken = {'RFG2', 'RFG3', 'RFG13', 'RPT13', 'RFG5', 'RFG12', 'RPT13', 'RPT14', 'RPT16', 'RPT8', 'RFG16', 'RST3'}; 

info.R1060M.badchan.epileptic = {'RAS1', 'RAS2', 'RAS3', 'RAS4', ... % little spikes
    'RPT10', 'RPT11', 'RPT12', 'RPT15', 'RPT5', 'RPT6', 'RPT7', ... % 89
    'RPT1', 'RPT2', 'RPT3', 'RPT4', 'RPT9', 'RST1', 'RST2', 'RST4', ... % 134
    'RFS6', 'RFS7', 'RFS8' ... % accompanies big IEDs
    }; 

% Line Spectra Info:
info.R1060M.FR1.bsfilt.peak      = [60, 79.9, 119.9, 159.8, 179.9, 200, 239.9];
info.R1060M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
% 42/153 - 0.27451, 16/72 - 0.22222, 101/292 - 0.34589, 58/179 - 0.32402
info.R1060M.FR1.session(1).badsegment = [177032,177442;180464,180731;186692,187142;187669,188308;192418,192941;217089,217471;220593,221178;238905,239329;240476,240804;244847,244922;244936,245372;246639,246941;248228,248987;252498,252896;258208,258558;260748,261108;266907,268000;269584,271342;281738,282000;291026,292517;294387,294900;298345,298679;301754,302787;323216,323626;333115,333624;346131,346626;351932,352791;353544,354286;356615,357136;364369,364705;365351,365674;368001,370000;382722,384000;388994,389477;396001,398000;409478,409775;419026,419380;429270,429660;434936,436000;437119,438411;440184,440467;442238,442671;448001,448519;453101,454270;455899,456261;459113,459521;461848,465168;488214,488731;490577,491059;501528,501857;503175,503803;521401,521630;526559,526965;544001,546000;582001,582427;582601,583051;586948,589263;591474,591519;592105,593507;611667,612000;617576,618729;636168,636356;659357,659722;708125,708425;710577,711068;726853,726985;728379,728785;730001,730475;742001,742971;747578,747892;754609,754910;776774,777047;778541,778941;804798,805108;819592,820000;826210,826858;830746,833884;836442,837207;838768,840274;848001,848525;857510,858862;861115,863118;877016,877374;878001,879219;898684,899644;902426,902737;903725,904169;906321,907537;928444,929092;930001,933920;934682,936000;936410,939890;959465,960000;962754,964000;964238,964564;967667,968000;973516,974000;980601,982967;984998,988354;991754,992000;996001,996411;1008119,1008425;1009588,1009962;1010001,1011017;1015832,1017894;1028921,1029436;1037250,1037557;1037572,1039485;1046315,1046824;1051828,1052193;1056071,1056403;1067889,1068928;1076001,1077188;1082001,1083285;1084585,1086892;1094001,1096000;1097643,1098257;1099274,1100787;1112001,1114832;1115238,1115644;1120343,1121126;1127558,1128000;1134506,1135781;1138218,1142000;1142877,1143102;1151492,1151920;1155498,1155801;1158629,1162000;1164956,1167851;1177486,1183398;1184001,1189712;1190001,1190475;1197067,1197595;1198651,1200000;1204748,1205269;1205282,1205509;1216238,1218000;1223897,1226000;1230001,1230701;1231810,1232930;1239899,1240354;1243530,1243944;1244851,1245319;1248516,1249110;1255764,1256000;1257081,1257342;1257468,1257769;1260835,1264000;1272095,1275493;1277260,1277966;1278454,1279837;1287681,1290612;1292154,1292437;1294547,1294810;1294901,1295567;1297752,1298000;1299290,1299646;1302001,1308000;1310813,1313102;1313425,1313874;1313901,1316203;1318792,1320000;1322488,1322965;1325856,1325988;1326001,1328580;1330416,1330886;1332001,1333029;1349383,1349539;1353554,1353805;1357292,1358000;1364131,1364384;1366238,1366662;1387441,1388000;1388575,1388953;1396494,1397626;1400414,1402000;1402136,1402576;1403621,1404000;1404027,1405156;1414397,1414733;1432609,1432967;1469349,1471128;1473846,1474719;1479296,1482000;1489578,1490000;1490665,1490967;1491663,1492000;1492994,1495194;1499200,1501178;1517762,1519565;1521798,1522602;1524001,1525130;1535131,1535618;1545451,1545849;1546001,1547007;1547502,1548963;1551635,1553065;1557300,1558000;1564315,1564465;1571423,1573092;1581925,1582284;1600381,1601972;1613457,1615563;1616001,1616413;1621520,1622000;1624001,1624900;1630869,1631180;1636905,1637333;1640254,1640469;1643091,1644000];
info.R1060M.FR1.session(2).badsegment = [1,894931;914782,915477;1064788,1065426;1187153,1188191;1200891,1201126;1208032,1415148];
info.R1060M.FR1.session(3).badsegment = [310446,311148;357601,358463;404240,405473;446805,447130;452845,453900;550166,551166;601105,601761;646825,647797;658083,658904;696331,697086;708857,709487;743191,744155;791062,792000;839663,840521;852617,853338;886309,887537;937596,938302;977264,977795;1031373,1032398;1080942,1081775;1122803,1123458;1180897,1181622;1190001,1190527;1266585,1267539;1296674,1297045;1317341,1317968;1415095,1416000];
info.R1060M.FR1.session(4).badsegment = [137308,138306;194420,195680;216289,216491;290001,291166;336001,336987;432367,433404;485675,486525;530001,530985;599123,599253;599459,599739;609701,611936;626931,628000;650140,650308;676001,676594;724537,725525;776113,776318];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1053M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Had to remove lots of IED channels. Remaining channels are ambiguous in terms of how much IED is still present.

% Channel Info:
info.R1053M.badchan.broken = {}; 

info.R1053M.badchan.epileptic = {'RPS1', 'RPS2', 'RPS3', 'RPS4', 'RTG1', 'RTG2', 'RTG3', 'RTG4', 'RTG5', 'RTG6', 'RTG7', 'RTG8', 'RTG9', 'RTG10', 'RTG11', 'RTG12', 'RTG13', 'RTG14', 'RTG17', 'RTG18', 'RTG19', 'RTG20', 'RTG21', 'ROS5'};

% Line Spectra Info:
info.R1053M.FR1.bsfilt.peak      = [60, 180, 190.2, 200, 224.5]; % manual
info.R1053M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1053M.FR1.session(1).badsegment = [189270,189660;197961,198170;225250,225912;232001,232344;235754,236679;237816,238000;248391,248550;262927,263412;265011,265345;331566,332197;385379,385680;393246,393807;408837,409096;411449,411896;433665,434171;442444,442626;457760,458096;504001,504703;553474,554000;568262,568650;625351,625698;627518,628185;634786,634902;678875,679654;688464,692000;731195,731634;746273,746949;751830,752636;774152,774878;776156,776483;804464,805001;867387,868000;892770,892951;902001,902848;917046,917775];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1001P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% Bad line noise (fat spectra in all of Session 1). Need to drop Session 1. 
% LAT1-4 and RAT1-4 are worrying synchronous, with spike followed by swoop and slight buzz. Relatively small fluctuations. Removing.
% Very clean.
% Small focal IEDs. 

% Channel Info:
info.R1001P.badchan.broken = {'LDA1', 'LDA2' ... % big fluctuations in Session 1, an antenna in Session 2
    }; 

info.R1001P.badchan.epileptic = {'LAT*', 'RP4', 'RP5', 'RP6' ...
    }; 

% Line Spectra Info:
info.R1001P.FR1.bsfilt.peak      = [60, 80, 120, 160, 180.1, 200, 220, 240.1];
info.R1001P.FR1.bsfilt.halfbandw = [0.8, 0.5, 0.5, 0.5, 1.4, 0.5, 0.5, 2.3];

% Bad Segment Info:
info.R1001P.FR1.session(1).badsegment = [1,2349060];
info.R1001P.FR1.session(2).badsegment = [174905,175354;176001,176245;181230,182000;182176,182439;220277,220703;271828,272773;295137,295384;305131,305350;325613,325886;379594,380000;388851,389938;423814,424554;463266,463551;473064,473348;485770,486000;489574,489811;494001,494380;546661,546912;552321,552975;567375,567712;571337,571573;572748,573219;588099,588388;597727,598000;635532,635668;636768,637233;638738,639255;664432,664838;715889,716078;719794,720000;745566,745942;777453,777922;790762,790932;796131,796525;810440,810975;845343,846000;853093,853505;892539,893035;912001,912300;940101,940473;950506,950806;1006081,1006403;1018037,1018723;1025746,1026729;1035484,1035779;1041598,1042000;1108146,1108354;1111298,1111702;1129826,1130000;1132001,1132344;1151286,1151757;1190391,1190707;1193177,1193724;1210827,1211160;1231375,1231676;1262450,1262769;1293403,1293787;1306522,1307225;1339048,1340000;1350256,1351201;1377234,1377666;1408156,1408515;1418001,1418427;1449369,1450000;1451548,1451791;1453022,1453430;1463548,1463823;1468510,1468886];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1002P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% Session 1 is all corrupted by line noise.
% Session 2 begins and ends with line noise, but the middle is salvageable.
% Removing large epileptic events.
% Cleaning line noise using non re-ref

% Channel Info:
info.R1002P.badchan.broken = {'RIF1', 'RIF2', 'RIF6' ... % antenna, also large fluctuations
    }; 

info.R1002P.badchan.epileptic = {'LMT2', 'LMT3', ... % segment 267
    'LMT4' % 313
    }; 

% Line Spectra Info:
info.R1002P.FR1.bsfilt.peak      = [60, 80, 120, 159.9, 180, 200, 220.1, 239.9];
info.R1002P.FR1.bsfilt.halfbandw = [0.6, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1002P.FR1.session(1).badsegment = [1,1532006];
info.R1002P.FR1.session(2).badsegment = [1,96831;133611,133648;173451,173835;223832,224135;250329,251009;268176,269047;275719,276660;347375,348000;490950,491493;512111,512689;512702,513170;533028,533420;539697,540072;540099,541074;589415,590358;625006,626179;627721,628207;633798,634969;661294,662538;690428,690872;752845,753976;755707,756000;809601,810374;827228,827632;865020,865606;979413,980336;992931,994000;1007780,1008403;1017298,1018403;1042760,1044469;1088061,1088695;1096655,1097370;1142645,1143638;1169224,1169960;1182873,1183988;1286869,1287279;1345804,1346675;1375778,1376521;1384001,1384866;1414001,1414713;1432627,1433626;1472643,1473811;1514829,1515505;1517824,1518709;1556688,1558469;1655667,1794044];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1003P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Lots of buzzing episodes

% Channel Info:
info.R1003P.badchan.broken = {'LG16', 'LG52', 'LG61', 'LG58', 'LG64', 'LG8', ... % antenna, also large fluctuations; Session 1
    'LG13', 'LG21', 'LG6', 'LG62', ... % session 2
    'LG39'}; % steps up and down a lot

info.R1003P.badchan.epileptic = {'MT2', ... % frequent sharp buzzes, larger fluctuations 
    'AT*', ... % segment 92
    'LG33', 'LG34', 'LG35' ... % segment 310
    }; 

% Line Spectra Info:
info.R1003P.FR1.bsfilt.peak      = [60, 80.1, 120, 180, 200, ...
    160.2, 240]; % last two from session 2
info.R1003P.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5, ...
    0.5, 0.5];

% Bad Segment Info:
% Session 1 60/207 - 0.28986, Session 2 93/262 - 0.35496 = 153/469
info.R1003P.FR1.session(1).badsegment = [173805,174362;182692,183906;184258,184493;186418,186894;188178,188795;189856,190469;210593,210926;216236,217501;219393,220179;227925,228540;254657,255025;258829,259618;262434,262511;276125,276650;277498,277896;295351,295678;297202,297593;328345,328773;342420,342568;345409,346000;347381,347904;373347,374163;380228,380354;393008,393604;399298,401602;401774,403049;404001,404316;405318,406816;428740,429398;436001,436709;440474,441575;446129,446433;446520,447295;457665,459243;461891,463227;494001,494419;496526,497080;498001,498644;515842,516600;535332,536000;544988,545229;556001,556233;569145,569868;576271,576687;584178,584781;589852,590671;593206,594193;594754,595537;596911,597591;598480,598935;600913,601551;602355,602523;604847,605327;612440,612652;617889,618521;618936,619098;623399,623922;624001,625700;626309,626515;638029,638267;675447,675648;693115,696459;697685,698000;718877,719319;719713,720372;723486,723686;730375,730453;733683,734000;735052,735648;740742,741704;742490,743188;750319,750989;759020,759485;770410,770618;771645,773374;783854,784326;787810,788795;789568,790000;823457,824000;834001,834761;840530,841277;841298,842453;843560,844449;864952,865321;868968,869118;869806,870473;904061,904926;935032,935519;940684,941501;946438,947279;989141,990205;1000996,1002000;1028591,1029194;1033224,1034556;1036275,1038747;1065794,1066000;1067266,1067678;1072823,1073382;1079532,1080316;1089449,1089952;1102595,1103201;1105399,1106396;1107550,1108257;1110627,1111198;1113089,1113317;1118001,1118457;1129014,1129805;1131685,1132274;1135260,1135372;1152482,1152832;1155024,1155283;1161459,1163880;1165218,1165277;1166218,1166576;1181738,1182679;1185056,1185378;1190402,1190860;1211355,1211825;1213155,1213495;1231173,1232586;1243510,1244521;1280001,1280783;1282694,1283356;1289300,1291507;1299830,1300274;1305252,1305458;1318849,1319368;1320313,1320705;1330174,1330824;1337326,1337718;1369873,1371207];
info.R1003P.FR1.session(2).badsegment = [321365,321406;328148,328771;340966,342000;355925,357039;363330,365686;366001,366503;417748,418403;427530,428326;435097,436660;458545,458983;462426,464000;465695,465745;499776,500366;505556,506122;508710,509491;524865,527041;571512,572511;601665,601730;619373,620475;625558,625654;666277,666941;672277,672854;688379,688935;696228,696717;715355,716920;763901,766941;768001,769053;801419,801718;812897,814000;814545,816000;838879,839003;849611,849831;856402,856519;892458,893350;903542,904977;908001,909376;913760,914719;932847,933333;940001,940967;946972,947201;961625,962276;963087,963664;982847,983567;995540,995690;996857,997003;997641,997684;1001187,1002360;1002631,1003521;1008811,1008890;1015568,1016741;1017167,1017761;1025389,1025732;1037421,1037535;1041167,1041211;1062514,1062818;1069869,1070098;1074629,1074747;1080724,1080806;1101528,1102757;1149181,1149827;1195590,1196799;1213818,1214374;1216001,1216961;1238843,1239037;1251099,1251416;1275320,1275833;1289643,1290671;1291588,1293307;1328545,1330405;1333062,1333612;1348873,1350000;1370934,1372000;1376641,1376669;1392001,1392536;1438001,1438658;1439026,1440000;1440422,1440491;1444164,1444251;1447909,1448000;1451665,1451757;1454375,1456000;1459171,1459251;1462921,1463005];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1006P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Session 1 has fat line spectra and extra blips in the 80 - 150 range. Not using.
% Ambiguous IEDs, quasi-channel breaks, buzzy looking. Not clean.
% Subjects from hospital P seem to have bad noise issues.
% IED at 284, 390; widespread, not removing channels

% Channel Info:
info.R1006P.badchan.broken = {'G16', 'G3', 'G12', 'G1', 'G33', 'G34', 'G35', 'G36', 'G37', 'G38', 'G39', 'G40', 'G42', 'G43', 'G49', 'G50', 'G51', 'G52', 'G53', 'G55', 'G56', 'G57', 'G58', 'G59', 'G44', 'G45', 'G8', 'G13' ... % big fluctuations
    }; 

info.R1006P.badchan.epileptic = {'AST1', 'AST2', 'MST1', 'MST2', 'PST4', 'G25', ... % segment 119
    'O1', 'P1', 'P2', ... % 139
    'P5', 'P6', 'P7', 'P8', ... % 160
    'PST1', 'PST2', 'PST3', 'G17', ... % 166
    'G18', 'G19', 'G26', 'G9', ... % 245
    'O2' ... % 333
    }; 

% Line Spectra Info:
info.R1006P.FR1.bsfilt.peak      = [60, 75, 80, 120, 125, 180.1, 200, 240, ...
    102.7, 160, 175];
info.R1006P.FR1.bsfilt.halfbandw = [1.2, 0.5, 0.5, 0.5, 0.5, 0.7, 0.5, 0.5, ...
    0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1006P.FR1.session(1).badsegment = [1,1785000];
info.R1006P.FR1.session(2).badsegment = [219603,219890;237474,237765;241008,241390;257711,258182;259810,260316;268535,269275;277572,278100;282371,282505;284265,284409;288882,288963;297701,297851;308155,308760;313117,313497;317870,318713;326627,326918;330420,330844;331050,331389;332280,332891;334184,334566;336437,336899;347921,348011;364358,364432;366462,369318;379022,379182;381081,381296;385860,386532;388471,388523;407618,408184;409517,409642;410533,410836;426001,426753;443091,443152;444822,444932;448745,448801;462056,462119;470249,470898;486537,489453;497162,497258;513454,515531;517295,517703;522650,523854;527970,528291;529692,529802;530974,531331;535244,535666;537539,538435;552935,553129;553738,553863;555882,555971;559212,559306;565155,566665;568806,569071;569975,570220;571797,572034;585501,585621;594189,594339;598133,598601;606225,606867;616313,616608;648017,648334;654967,655290;658681,659092;664919,669488;684136,684560;748638,749051;775120,781148;783609,783821;845618,845989;850258,850412;864082,865320;867229,868395;873564,874237;881727,882960;936721,936992;937532,939259;948139,948202];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1018P %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Mildly ambiguous buzz across channels, but not particularly large.
% Removed some channels, but not strong IEDs. According to Kahana, parietal, motor region seizure onset zone

% Channel Info:
info.R1018P.badchan.broken = {'RO5', 'RO6'}; % large fluctuations

info.R1018P.badchan.epileptic = {'RTP4', 'RTP5', 'RTP6', ... % 130
    'RTP3', 'RO8', 'RTP2', 'RTP1', ... % 201/348
    'LTP1', 'LTP2' ... % 466
    }; 

% Line Spectra Info:
info.R1018P.FR1.bsfilt.peak      = [60, 120, 180, 200, 240, ...
    75, 80, 125, 160];
info.R1018P.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5, ...
    0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1018P.FR1.session(1).badsegment = [258250,258588;315131,315311;348359,348455;401020,401342;412331,414000;508972,509299;534946,535235;552569,553555;641416,642239;694923,695213;699907,699952;856899,857587;922923,925690;930801,931430;976001,976340;978518,979861;980001,982000;1036726,1038590;1174208,1174536;1220001,1221370;1242504,1243591;1243629,1245537;1263200,1264924;1267288,1269960;1270678,1274000;1344258,1346000;1382567,1382886;1395165,1395878;1396001,1396388;1412001,1412352;1418037,1420000;1462001,1462233;1480001,1481049;1506454,1507394;1511689,1512000;1558410,1560000;1573222,1573430];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1036M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Big IEDs in ltl, but containable
% IED at 813, multiple channels, did not remove channels

% Channel Info:
info.R1036M.badchan.broken = {'LITG1', 'LSTS1', ... % big fluctuations
    'LAPS1', ... % small sharp blips
    'LAPS2', 'LAPS3', 'LAPS4'}; % big swoops

info.R1036M.badchan.epileptic = {'LITG6', ... % swoops and spiky   
    'LAST3', 'LAST4', 'LITG10', 'LITG11', 'LITG5', 'LITG9', 'LPST1', 'LSTS4', 'LSTS5', ... % 160
    'LITG12', 'LITG13', 'LITG14', 'LITG15', 'LITG16', 'LPST2', ... % 205
    'LPST3', 'LPST4' % 361
    }; 

% Line Spectra Info:
info.R1036M.FR1.bsfilt.peak      = [60, 120, 180, 200, 240, ...
    79.9];
info.R1036M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5, ...
    0.5];

% Bad Segment Info:
info.R1036M.FR1.session(1).badsegment = [227895,228229;255081,255426;273649,275432;282555,283249;290001,290441;319179,319726;349725,350211;369347,370000;409367,409902;423871,424054;426406,427207;428694,429303;465353,465924;478855,479448;496988,497920;504825,505229;525468,526000;533351,533892;560994,561497;610865,611769;622798,623299;632915,633182;641169,641664;668440,669158;682913,683499;721032,721581;734450,735055;750299,750721;787238,787700;811611,811849;824222,824642;841570,842000;842573,842735;858051,858469;865518,866727;867713,868531;871673,872392;907556,908000;909210,909890;916567,917092;917185,917924;920121,920755;925185,926000;933268,933853;937393,937853;981296,981708;986704,987076;987393,987658;1036591,1036731;1037306,1037771;1080325,1081041;1084093,1084479;1094758,1095188;1100001,1100562;1114976,1115507;1123052,1123501;1132549,1133188;1142117,1142997;1143351,1144000;1144585,1145172;1145744,1145958;1155274,1155791;1195528,1195906;1254557,1255033;1257324,1258000;1267669,1268640;1270001,1271612;1271667,1272000;1272043,1273495;1276408,1276932;1281556,1282153;1326152,1326443;1327683,1327972;1346075,1346664;1385532,1385745;1441218,1441432;1467938,1468421;1490978,1491521;1507431,1508000;1584444,1584975;1594807,1594999;1596148,1596433;1598734,1599035;1617345,1617481;1624861,1625471;1647744,1648229;1655609,1656300;1658764,1659076;1670297,1670769];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1039M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Major IED section in the middle, across multiple channels. Marked, did not remove channels.

% Channel Info:
info.R1039M.badchan.broken = {'RPPS5', 'RPTS8'}; 

info.R1039M.badchan.epileptic = {'RFPS1',...
    'RIHS6', 'RIHS7' ... % 340
    }; % 'RFPS*', 'ROFS1', 'ROFS2', 'ROFS4', 'ROFS5', 'ROFS7', 'ROFS8', 'RIHS5', 'RIHS6', 'RIHS7', 'RIHS8'}; % swooping together

% Line Spectra Info:
info.R1039M.FR1.bsfilt.peak      = [60, 120, 180, 200, 240, ...
    79.9, 103.5, 109.7, 160.1];
info.R1039M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.6, 0.5, ...
    0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1039M.FR1.session(1).badsegment = [281256,281513;281824,282104;301324,301730;323014,323134;324001,324451;327713,328322;328680,328965;337854,338072;368001,368380;486234,486546;492301,492650;511657,512000;516680,517237;536444,536971;550138,550574;562363,563593;629770,630102;678158,679640;693538,693894;701709,702130;766585,767100;790345,790773;813798,814247;833558,833898;835177,835668;842001,842233;843328,844000;863717,864000;928361,928568;928883,929023;929292,929420;929449,935000;935661,936471;936874,937557;938119,938779;939440,941763;942229,942822;944295,944562;945603,946000;947343,947853;948585,949194;1041584,1042000;1085228,1085986;1089826,1090213;1113848,1114239;1141814,1142157;1203734,1204000;1206408,1206844;1241675,1242253;1254861,1255031;1267447,1267996;1287840,1288322];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1042M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Subject has IEDs the entire time in a handful of channels.
% Removed lots of IED channels. Removing mostly buzzing episodes, some of them very small. 

% Channel Info:
info.R1042M.badchan.broken = {'RTG30'}; % antenna 

info.R1042M.badchan.epileptic = {}; % 'RPD1', 'RTG10', 'RTG11', 'RTG13', 'RTG1', 'RTG2', 'RTG3', 'RTG4', 'RTG5', 'RTG6', 'RTG18', 'RTG19', 'RTG21', 'RTG25', 'RTG26', 'RTG27', 'RTG32', 'RTG35'};

% Line Spectra Info:
info.R1042M.FR1.bsfilt.peak      = [60, 120, 180, 200, 240];
info.R1042M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1042M.FR1.session(1).badsegment = [164484,164711;165151,165372;306557,306765;312591,313708;328875,329595;359173,359559;365879,366439;367328,367857;377258,377851;401064,401466;475639,476413;561107,561466;580402,580791;581195,582380;621774,622000;686452,686787;689538,689930;704160,704304;726990,728687;798001,799136;837125,837849;838001,838370;839488,840344;842252,842959;843242,843712;844001,844344;844805,845035;854684,855295;865506,865646;870905,871630;943353,943749;1031034,1031235;1054599,1055424;1056001,1056251;1056811,1057686;1058522,1058818;1059214,1059434;1060718,1061479;1062001,1062594;1067447,1067910;1069516,1069811;1121286,1121636;1155175,1155501;1156541,1156935;1158001,1159551;1160001,1162000;1219570,1220203;1224363,1224906;1260099,1260529;1305572,1308000;1309530,1309612;1311139,1311513;1330460,1331031;1341707,1341940;1342001,1342783;1351542,1352000;1352347,1352922;1404682,1405890;1426430,1426965;1436557,1436729;1478722,1479146;1509540,1509654;1511409,1512223;1514406,1515102;1518474,1518548;1538728,1539817;1544819,1545094;1552325,1552588;1582214,1582308;1584627,1584781;1586091,1586360;1586770,1586874;1587615,1587692;1588001,1588538;1589538,1589616;1590234,1590396;1590984,1591344;1596001,1596683;1617659,1617986;1618637,1619668;1620541,1623227;1623272,1625626;1626001,1628000;1629635,1629992;1636001,1636932;1641014,1641207;1650001,1650324;1769103,1769940;1780875,1781112;1805179,1807317;1840478,1840763;1904934,1905291;1917189,1918856;1919508,1919815;1927641,1928000;2026001,2027078;2068353,2069388;2070250,2070872;2077687,2077982;2080333,2080683;2094402,2095652;2110297,2110642];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1050M %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: Some channels constantly IED. Larger IEDs bleeding into other channels. If were to remove all trials with IED, likely none left.

% Channel Info:
info.R1050M.badchan.broken = {'LPG1'}; 

info.R1050M.badchan.epileptic = {'LPG19', 'LPG20', 'LPG21', 'LPG22', 'LPG23', 'LPG28', 'LPG30', 'LPG31', 'LPG39'};

% Line Spectra Info:
info.R1050M.FR1.bsfilt.peak      = [60, 180, 200];
info.R1050M.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1050M.FR1.session(1).badsegment = [31883,31944;32327,32411;32474,32519;33282,33342;34855,34941;36067,36110;36881,36920;39246,39317;44698,44779;57869,57966;62269,62771;69083,69150;73681,73898;88061,88139;89143,89235;90053,90137;91296,91376;91738,91817;91905,92000;92676,92747;93226,93317;93709,93807;95189,95287;97834,97920;98035,98265;99103,99198;100001,100118;138001,138082;142377,142717;144498,145487;148321,148935;149812,149890;152182,152290;152653,152769;153266,153388;155316,155436;158905,159019;160635,160765;163653,163775;165195,165233;168293,168407;182940,183019;190748,190846;202001,203118;206962,208290;219453,219549;233894,234092;234619,234922;245802,246366;246990,247076;270162,270493;276960,277166;293137,293301;304740,305394;305534,305650;322067,322505;333457,333541;337056,337261;337744,337809;339212,339263;340426,340489;341347,341471;342186,342296;346001,346231;350796,350862;368903,368971;378166,378523;381044,381227;395643,396000;396379,396461;397679,398000;399854,400337;400684,401118;402464,402578;403141,403213;403558,403634;405570,405670;407738,407837;409415,409497;410085,410207;411580,411684;412422,412517;412903,412985;416142,416231;426482,427471;427534,427785;428001,428461;429163,429267;431946,432038;438627,438691;438921,439140;449502,449575;455536,455606;456033,456141;459871,460257;461129,461227;461850,463186;466528,468000;468514,468610;476238,476354;489369,490000;496764,497791;504001,504086;508915,509009;524690,524763;530547,530834;532001,532409;534339,534445;550037,550322;557669,558294;561161,561495;563040,563104;565586,565640;565951,566055;572011,572096;573107,573192;575427,575904;588960,589047;590214,590306;614875,615636;620815,620908;627580,627684;632266,632362;644337,644570;649185,649265;669854,669958;673423,673962;677246,677702;678690,678802;681647,681741;682131,682519;682978,683301;685671,685779;707641,707755;710988,711076;713461,713545;714395,714495;716661,716737;717091,717201;722001,722874;730089,730167;730599,730687;736952,737051;749854,749944;809093,809263;825719,825872;826001,826677;835488,835565;862635,862719;867814,867902;868589,868675;869723,869809;876404,876485;877729,877807;878732,878830;879603,880175;903572,903660;913242,914943;917590,917672;920212,920519;921534,922000;922071,922177;924182,924259;924803,924912;931270,931352;934242,934570;938210,938767;961631,962000;963268,963356;967860,968110;968595,969184;981810,981882;983064,983358;983719,984527;985701,985801;986931,987041;989520,989591;989911,989992;990863,991156;991721,991960;992289,992346;995697,995787;998474,998546;1011574,1011849;1013062,1013317;1014629,1014894;1016446,1016741;1041326,1041769;1042722,1043136;1048269,1048344;1051415,1051559;1052982,1053068;1054861,1054955;1055546,1055638;1056001,1056104;1069677,1069886;1070432,1070743;1088913,1089213;1089846,1090126;1090539,1090953;1109846,1110000;1117204,1117269;1121419,1121485;1126001,1126731;1127764,1128282;1147901,1148290;1156474,1156646;1157887,1157934;1167901,1168358;1173445,1173509;1174478,1174586;1176764,1176858;1177937,1178207;1182528,1182592;1187580,1187658;1193774,1193853;1212037,1212350;1231738,1232118;1236653,1237172;1238962,1239021;1241161,1241267;1252001,1252961;1253409,1253475;1256823,1257235;1277286,1278000;1280938,1281031;1281482,1281581;1284001,1284324;1285389,1285473;1285830,1285908;1289153,1289241;1289889,1289994;1290694,1290880;1299756,1299825;1303738,1303797;1304919,1304985;1309748,1309825;1316893,1316977;1318001,1318447;1322710,1322804;1323661,1323904;1324204,1324310;1324518,1324606;1324984,1325080;1325887,1325954;1342817,1343126;1353699,1353781;1355552,1355638;1356692,1357118;1368595,1368662;1379516,1379599;1380047,1380145;1384869,1384949;1400817,1401382;1402535,1402620;1403762,1403855;1408678,1408767;1414230,1414517;1415508,1415638;1421157,1421237;1425024,1425110;1457139,1457442;1460347,1460415;1461637,1461724;1464379,1464461;1466166,1466243;1467236,1467408;1467445,1467759;1468847,1468906;1490442,1490810;1493538,1493614;1501091,1501622;1506281,1507152;1512333,1512437;1514490,1514544;1516273,1516310;1516720,1516793;1517689,1517992;1518962,1519009;1519435,1519523;1524001,1524072;1538458,1538493;1539278,1540000];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1020J %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1020J' - 1    - 24T  - 21F   - 114/300   - 0.3800   - 8T   - 18F   - 102/279   - 0.36559  - :)  - Done. Confirmed.

% Kahana: LTL + mPFC onset zone
% Me: LTL + mPFC + motor + occipital

% IEDs are ambiguous, seemingly widespread.
% Frequent buzz episodes. 
% On re-clean, unmarked some buzz episodes whose amplitudes were not as strong, less apparent across channels.
% Re-clean had virtually no effect on trial number, so buzz episodes seem to be between trials.

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
% Slightly careful with HFA and slope. [NOTE: after looking through the data again, great for slope]
% Some removal of additional buzz with jumps, but not much.

% Channel Info:
info.R1020J.badchan.broken = {'RSTB5', 'RAH7', 'RAH8', 'RPH7', 'RSTB8', 'RFB8', ... % my broken channels, fluctuations and floor/ceiling. Confirmed.
    'RFB4', ... % one of Roemer's bad chans
    'RFB1', 'RFB2', 'RPTB1', 'RPTB2', 'RPTB3'}; % Kahana broken channels

info.R1020J.badchan.epileptic = {'RAT6', 'RAT7', 'RAT8', 'RSTA2', 'RSTA3', 'RFA1', 'RFA2', 'RFA3', 'RFA7', ... % Kahana seizure onset zone
    'RSTB4', 'RFA8' ... % after buzzy episodes, continue spiky (like barbed wire)
    'RAT*', ... % synchronous little spikelets, intermittent buzz. Also very swoopy. Confirmed confirmed.
    'RPTB6', ... % added on re-clean
    'RPTA6', 'RPTB7', 'RSTC4', 'RSTC5', ... % IED, 386
    'RSTB7', ... % IED, 418
    'RSTA4' ... % IED, 675
    }; 

% Line Spectra Info:
% Session 1/1 z-thresh 0.45, 1 manual (tiny tiny peak), using re-ref. Re-ref and non-ref similar spectra.
info.R1020J.FR1.bsfilt.peak      = [60  120 180 219.9 240 300 ...
    190.3];
info.R1020J.FR1.bsfilt.halfbandw = [0.5 0.5 0.7 0.5   0.5 0.8 ...
    0.5];

% Bad Segment Info:

% Focused primarily on removal of buzzy episodes, also on some episodes where RSTB7 has big fluctuations
% info.R1020J.FR1.session(1).badsegment = [222,425;21169,21462;94052,94252;306967,307168;447445,447647;499311,500554;508251,508716;553916,554937;578019,580740;622218,623275;668182,668792;937194,938417;948517,950659;1023532,1024720;1049122,1049977;1061343,1062002;1153784,1157155;1218605,1221167;1335219,1337563;1470021,1472000;1541100,1543946;1551198,1551791;1559549,1560000;1669122,1669848;1770421,1773973;1840485,1842900;1940356,1941288;1942113,1943574;1944162,1947058;1948727,1949010;1950605,1951421;1951509,1953930;2040513,2042489;2180001,2180611;2282545,2283013;2296392,2297288;2323413,2326543;2340670,2342784;2478525,2479570;2553863,2554364;2556896,2557381;2573988,2574872;2650561,2651735;2653851,2655606;2699065,2699932;2963848,2967067;3230319,3232379;3280702,3281461];

% Unmarked some buzzy episodes, added more ambiguous IEDs.
info.R1020J.FR1.session(1).badsegment = [222,425;21169,21462;94052,94252;306967,307168;447445,447647;578019,580740;622218,623275;948517,950659;1023532,1024720;1153784,1157155;1218214,1221167;1335219,1337563;1469335,1472000;1475593,1477756;1541100,1543946;1551198,1551791;1559549,1560000;1669122,1669848;1770421,1773973;1840485,1842900;1944162,1947058;1952882,1953930;2040513,2042489;2180001,2180611;2323413,2326543;2340670,2342784;2573988,2574872;2653851,2655606;2699065,2699932;2963848,2967067;3230319,3232379;3280702,3281461];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1032D %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% Kahana: MTL onset zone
% Me: LTL + lPFC

% Not enough LTL surface channels after cleaning. Clear IED across all of them.
% Artifact marking is not complete. 

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
% Great for HFA and slope. [NOTE: VERY WRONG. JUMPS ALGORITHM IS DETECTING A LOT OF BUZZ]
% Lots of buzz detected by jumps.
% OK, after removing a ton of buzz channels, I am confident that no buzz remains.

% Channel Info:
info.R1032D.badchan.broken = {'LFS8', 'LID12', 'LOFD12', 'LOTD12', 'LTS8', 'RID12', 'ROFD12', 'ROTD12', 'RTS8', ... % flat-line channels
    };

info.R1032D.badchan.epileptic = { ...
    'LFS1', 'LFS2', 'LFS3', 'LFS4', 'LTS1', 'LTS2', 'LTS3', 'LTS4', 'LTS5', 'LTS6', ... % IED, 145
    'RTS*' ... % IED, 63
    };

%     'RFS7', 'RFS8', ... % very spiky. Removing after using jump algorithm.
%     'LTS1', 'LTS2', 'LTS7', 'LFS7', 'RTS1', 'RTS2', 'RTS7', ... % very spiky. Removing after using jump algorithm.

% Line Spectra Info:
% Session 1/1 z-thresh 1 re-ref, no manual. 
info.R1032D.FR1.bsfilt.peak      = [60   120  180  240  300];
info.R1032D.FR1.bsfilt.halfbandw = [0.5, 0.5, 0.5, 0.5, 0.5];

% Bad Segment Info:
info.R1032D.FR1.session(1).badsegment = [295956,297228;318272,319731;323646,324666;347892,349415;380137,381092;382349,383266;390578,390775;401990,403228;411943,412718;423518,424112;424978,425778;428364,429396;437737,438531;455672,456196;498245,499870;506647,508486;510769,511531;575342,576101;604775,605989;642569,642789;693279,694441;771524,772286;811091,811653;815633,816409;852995,853531;860491,861550;890292,891260;920736,923506;926162,927795;959791,960559;966378,966972;967376,970286;976526,977254;985493,986278;989072,989834;992204,993415;1010691,1011169;1034124,1035563;1050131,1051189;1062401,1064673;1082311,1082983;1104014,1105318;1127421,1127764;1197318,1199234;1206072,1206718;1213672,1214305;1226994,1228208;1228285,1234395;1234642,1235747;1259820,1260782;1261898,1268293;1283646,1284982;1297923,1298827;1300111,1301789;1312318,1313306;1327098,1327725;1366911,1367815;1384272,1385041;1395253,1396254;1399046,1399763;1429292,1430092;1536718,1538867;1541523,1542202;1611640,1612247;1634466,1636086;1686033,1686950;1699588,1700131;1708460,1710030;1736221,1738479;1787672,1788725;1837040,1837738;1838892,1840138;1864285,1865093;1923091,1924028;1936795,1938195;1942878,1943705;1984382,1986067;2001414,2002124;2004047,2005609;2006246,2008679;2017105,2017473;2026551,2027673;2028056,2029115;2060252,2060531;2071556,2072769;2075124,2075815;2102575,2103537;2134085,2134480;2140562,2143208;2154046,2155234;2218188,2218937;2275840,2276383;2296136,2296769;2302240,2303731;2379240,2380105;2490021,2490486;2491234,2491873;2575782,2576976;2683169,2684047;2769040,2770731;2773872,2774402;2787653,2788899;2836318,2837015;2873924,2874473;2878446,2878970;2909427,2910299;2920190,2920362;2954453,2954673;3007272,3007944;3031504,3032144;3036690,3037490;3037711,3038208;3048930,3049770;3061200,3062032;3104111,3104751;3189285,3190144;3240588,3241376;3250570,3251785;3282078,3282602;3343072,3343667;3351188,3351808;3369575,3370196;3386492,3387054;3392214,3393009;3401504,3402880;3404462,3405264;3405585,3406403;3418892,3419667;3454246,3455021;3478498,3479073;3482918,3484080;3484956,3485531;3493789,3494465;3507201,3507783;3524524,3525387;3530969,3531792;3556860,3557689;3564590,3566094;3574333,3575436;3585137,3587221;3596424,3597255;3625111,3625738;3649853,3650396;3679416,3680366;3692027,3692846;3718348,3719571;3723743,3724473;3734614,3735350;3813557,3814279;3817580,3818101;3831169,3831828;3843285,3844060;3914453,3915131;3930743,3931893;3987918,3988338;4014368,4015170;4040274,4040510;4042680,4042929;4062736,4063511;4065769,4065983;4074446,4075021;4081124,4082815;4084260,4084738;4097917,4098209;4137227,4138550];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1033D %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% Kahana: LTL + parietal
% Me: LTL + parietal + occipital

% MASSIVE IED events that hit all channels
% Really ugly. Big drifts. 

% Removed buzz and IED events, lots of large and some small blips that carry through from depths.
% Remaining surface channels have frequent slow drifts.
% Even if this subject had ended up with enough trials, I would not trust them. [EDIT: maybe not that bad].
% LTS6 and LTS7 were originally marked as broken/epileptic (high frequency noise/spiky slinkies). New cleaning kept them in.
% Stopped because patient was having trouble focusing.
% Prioritizing trials over channels.
% Not that bad of a subject, really.
% I'm guessing not too many ambiguous events remain. 
% Very clean lines.
% Some addition of buzz via jumps.

% Channel Info:
info.R1033D.badchan.broken = {'LFS8', 'LTS8', 'RATS8', 'RFS8', 'RPTS8', 'LOTD12', 'RID12', 'ROTD12'... % flat-line channels
    'LOTD6'}; % large voltage fluctuations; might be LOTD9

info.R1033D.badchan.epileptic = {'RATS*' ... % Kahana
    'RPTS*', ... % IED bleedthrough from depths. Prioritizing trials over channels.
    'LTS7' ... % constant high frequency noise. Removed after jumps.
    };
  
% Line Spectra Info:
info.R1033D.FR1.bsfilt.peak      = [60.1 120 180 240 300];
info.R1033D.FR1.bsfilt.halfbandw = [0.5  0.5 0.5 0.5 0.5];

% Bad Segment Info:
info.R1033D.FR1.session(1).badsegment = [28115,28917;39804,40613;52925,56006;73056,73865;83175,83988;85883,86686;108201,109004;129871,132027;141085,142219;151314,153203;267876,269444;305614,306416;350496,351838;358212,359012;360692,361492;373188,374576;389439,390400;411731,423465;465536,467200;468382,473498;480602,481893;484182,487497;538621,538680;540524,542331;557718,558925;594181,598247;696936,699215;711098,715176;728117,729550;754264,760086;776356,778157;808988,813267;856558,858639;934401,935351;940046,942415;947201,948409;970504,971840;977872,979712;1010472,1011200;1052943,1054860;1064092,1065215;1157659,1161789;1176597,1181432;1336449,1340215;1387536,1392086;1395569,1399163;1402653,1406015;1441848,1443044;1518072,1520054;1528175,1529600;1531685,1533241;1537769,1540550;1588221,1589609;1618472,1627325;1637532,1639125;1641130,1643692;1647698,1649595;1655207,1656260;1656384,1660183;1678118,1680660;1703092,1705570];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1034D %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% Kahana: lPFC + motor
% Me: lPFC + motor + LTL

% Very drifty. Not natural looking.
% Some channels remaining that have ambiguous IEDs. Perhaps an unreliable subject.

% 21/131 - 0.16031
% 16/255 - 0.062745
% 3/80 - 0.0375

% 40/466

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
% Jumps is picking up stuff that with LP are removed. Not much change.

% A somewhat ambiguous subject, with large fluctuations (especially in LTS) that may or may not affect phase encoding.
% High frontal coverage, so interesting test subject for phase encoding.
% Great for HFA and slope. 

% Channel Info:
info.R1034D.badchan.broken = {'LFG1', 'LFG16', 'LFG24', 'LFG32', 'LFG8', 'LIHG16', 'LIHG24', 'LIHG8', 'LOFG12', 'LOFG6', 'LOTD12', 'LTS8', 'RIHG16', 'RIHG8', ... % flat-line channels
    'LOTD7'}; % large voltage fluctuations

info.R1034D.badchan.epileptic = {'LIHG17', 'LIHG18'... % big fluctuations and small sharp oscillations. Confirmed.
    'LOFG10', ... % frequent small blips, removed during second cleaning. Confirmed.
    'LFG13', 'LFG14', 'LFG15', 'LFG22', 'LFG23', ... % marked by Kahana
    'LTS3', 'LTS4', 'LTS5', 'LTS6' ...
    }; 

% Line Spectra Info:
% Combined re-ref, has spectra for all sessions. z-thresh 1 + manual
info.R1034D.FR1.bsfilt.peak      = [60  120 172.3 180 183.5 240 300 305.7 ...
    61.1 200 281.1 296.3 298.1];
info.R1034D.FR1.bsfilt.halfbandw = [0.5 0.5 0.5   0.5 0.5   0.6 0.9 0.5 ...
    0.5  0.5 0.5   0.5   0.5];
     
% Bad Segment Info:
info.R1034D.FR1.session(1).badsegment = [418859,420105;443382,444751;576389,580731;927897,929035;1065949,1066828;1119020,1122286;1157962,1158977;1214827,1215892;1416659,1419518;1547646,1548234;1552020,1561253;2248530,2248647;2267565,2267826];
info.R1034D.FR1.session(2).badsegment = [446407,448990;452969,454932;520027,521467;600181,601137;605891,606563;618395,619408;620442,621784;683201,683660;683730,684040;689659,690395;690562,691086;735233,735602;736563,737054;790337,790860;849659,850647;973789,974886;992969,994299;1073716,1081380;1096163,1097196;1104836,1108258;1222937,1224118;1229213,1230936;1307459,1308570;1370015,1370627;1444275,1445070;1448298,1451228;1493901,1494632;1693569,1694092;1734660,1735848;1765949,1769447;1771052,1772595;1789724,1791118;1890633,1891421;1956859,1958400;2028786,2030712;2037840,2039137;2056840,2058009;2083801,2084241;2099369,2099809;2149123,2150400;2158453,2159957;2193910,2194466;2244104,2244679;2246119,2246950;2259324,2259951;2270001,2271305;2313266,2315505;2409511,2410021;2436324,2437769;2440563,2441421;2509285,2510215;2549466,2551815;2694847,2696712;2745853,2747196;2748401,2749092;2750285,2751505;2790666,2791583;2937601,2943408;3077710,3078400;3079705,3080918;3112034,3112725;3123201,3124235;3193472,3194713;3200298,3201067;3338078,3339789;3342511,3346956;3378279,3379612;3428040,3428853;3434633,3438744;3491324,3492415;3495788,3497086;3571679,3572615;3628294,3629335;3692054,3698287;3731285,3732454;3772982,3773983;3775820,3777053;3790388,3791505;3796498,3797525;3860995,3863402;3871085,3872000;3956795,3958292;4015337,4016286;4017201,4018021;4027408,4027905;4134866,4136131;4262401,4263912;4301679,4302512;4312027,4313040];
info.R1034D.FR1.session(3).badsegment = [54931,55505;100734,101054;102527,102847;103066,103386;259321,259641;334698,335280;337994,339200;356885,357847;376207,377460;398846,399860;425825,426750;475356,476105;514240,515241;516033,517182;521633,522744;523575,524621;527524,528376;570118,570938;571808,575021;600027,600731;659344,660473;663261,666830;668093,669692;672608,674589;749679,750680;819201,820873;858672,862415;868897,870569;972245,973578;977730,978724;1006576,1007434;1017918,1018751;1031143,1032486;1061788,1062866;1082782,1083654;1087343,1087711;1123820,1124466;1175814,1176898;1185298,1188208;1250072,1251034;1307872,1310615;1335620,1336737;1337177,1338529;1380414,1382376;1403666,1404234;1406710,1407079;1408885,1412931;1415634,1417028;1425388,1427200;1428892,1429609;1433354,1434687];

% Unmarked patches with slow drifts.
info.R1034D.FR1.session(1).badsegment = [576389,580731;1065949,1066828;1214827,1215892;1547646,1548234;2248530,2248647;2267565,2267826];
info.R1034D.FR1.session(2).badsegment = [446407,448990;452969,454932;605891,606563;618395,619408;620442,621784;683201,684034;689659,690395;690562,691086;735233,735602;736563,737054;790337,790860;849659,850647;973789,974886;992969,994299;1096163,1097196;1104836,1108258;1222937,1224118;1229213,1230936;1307459,1308570;1370015,1370627;1444275,1445070;1448298,1451228;1493901,1494632;1693569,1694092;1734660,1735848;1765949,1769447;1771052,1772595;1789724,1791118;1890633,1891421;1956859,1958400;2028786,2030712;2037840,2039137;2056840,2058009;2083801,2084241;2099369,2099809;2149123,2150400;2158453,2159957;2193910,2194466;2244104,2244679;2246119,2246950;2259324,2259951;2270001,2271305;2313266,2315505;2409511,2410021;2436324,2437769;2440563,2441421;2509285,2510215;2549466,2551815;2694847,2696712;2745853,2747196;2748401,2749092;2750285,2751505;2790666,2791583;2937601,2943408;3077710,3078400;3079705,3080918;3112034,3112725;3123201,3124235;3193472,3194713;3200298,3201067;3335788,3337099;3338078,3339789;3342511,3346956;3378279,3379612;3428040,3428853;3434633,3438744;3491324,3492415;3495788,3497086;3571679,3572615;3628294,3629335;3731285,3732454;3772982,3773983;3775820,3777053;3790388,3791505;3796498,3797525;3860995,3863402;3871085,3872000;3956795,3958292;4015337,4016286;4017201,4018021;4027408,4027905;4134866,4136131;4262401,4263912;4301679,4302512;4312027,4313040];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1045E %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: 

% Kahana: MTL + occipital
% Me: MTL + LTL + occipital

% Clear IEDs + buzz
% Otherwise, reliable

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
% Jumps did not add any segments.

% Buzz is main concern, but these seem mostly discrete. Not great for slope, but not awful. Would be ok.
% But great coverage for phase encoding, though watch out for LATS1-4 [NOTE: these channels are now removed]

% Channel Info:
info.R1045E.badchan.broken = {'RPHD1', 'RPHD7', 'LIFS10', 'LPHD9', ... % large fluctuations
    'RAFS7', ... % very sharp spikes
    'RPTS7' ... % periodic sinusoidal bursts
    };

info.R1045E.badchan.epileptic = {'LAHD2', 'LAHD3', 'LAHD4', 'LAHD5', ... % Kahana
    'LMHD1', 'LMHD2', 'LMHD3', 'LMHD4', 'LPHD2', 'LPHD3', 'LPHGD1', 'LPHGD2', 'LPHGD3', ... % Kahana
    'LPHGD4', 'RAHD1', 'RAHD2', 'RAHD3', 'RPHGD1', 'RPHGD2', 'RPHGD3', ... % Kahana
    'LATS1', 'LATS2', 'LATS3', 'LATS4', 'LATS5', ... % constant coherent high amplitude slink with IEDs
    'RATS1', 'RATS3' ... % re-clean 445
    }; 

% Line Spectra Info:
% Session 1/1 z-thresh 2 on re-ref, no manual. 
info.R1045E.FR1.bsfilt.peak      = [59.9 179.8 299.6];
info.R1045E.FR1.bsfilt.halfbandw = [0.5  0.5   0.5];

% Bad Segment Info:
% Have to remove sample 2603373 onward b/c of file corruption.
% Added bad segments of big spikes.
info.R1045E.FR1.session(1).badsegment = [171692,172466;210724,210924;211037,211298;302424,303297;379905,380323;426456,427376;430634,432786;489664,492021;572750,573448;573918,575147;603046,604538;668795,670121;763031,763858;777706,778508;878339,879120;889324,892020;960986,961515;983367,984697;1052995,1054103;1077390,1079768;1117845,1119861;1197221,1199374;1258241,1259725;1271357,1273408;1282717,1284824;1354645,1355991;1396977,1398600;1433457,1434735;1460994,1463412;1559206,1561104;1581212,1582413;1610941,1613273;1635295,1637809;1657760,1659643;1693909,1694523;1754297,1756481;1777092,1778705;1848710,1848868;1852916,1854144;1955418,1959202;1986013,1986985;2021977,2023589;2121877,2125386;2160249,2161882;2202546,2205761;2241007,2242652;2317358,2318906;2346414,2349258;2355489,2359704;2360718,2364755;2366930,2369073;2410999,2411604;2436867,2439423;2444171,2444981;2463933,2465227;2500654,2502823;2503692,2504760;2603221,2916214];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1059J %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% Kahana: MTL + LTL + occipital
% Me: lPFC, LTL, MTL, ...

% Clear IEDs + buzz. Some slink in IED channels that is ambiguous.
% Clean data. 
% Based on performance, number of total channels, and number of epileptic channels, some questions about health of patient

% 8/92 - 0.086957
% 22/223 - 0.098655

% 30/315

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
    'LAT8', 'LSTA7', 'RPT7', 'RSTA8', ... % constant spiky. Removed after jumps.
    'LAT1', 'LAT2', 'LAT3', 'LAT4'}; % Kahana

% Line Spectra Info:
info.R1059J.FR1.bsfilt.peak      = [60  180 240 300];
info.R1059J.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5];

% Bad Segment Info:
info.R1059J.FR1.session(1).badsegment = [133,336;1444,1649;4217,4417;11194,11395;14400,14601;19424,19624;21392,21592;26401,26675;28301,28503;28521,28721;28787,29004;30613,30813;30877,31077;41260,41473;53530,53740;59526,59782;63666,63971;79875,80075;81382,81582;82645,82915;85017,85217;89073,89289;89728,90002;90409,90611;98386,98759;98804,99005;100897,101101;102260,102622;102744,102944;103599,103818;106191,106391;118480,118681;123206,123406;129303,129504;135671,135872;136997,137201;144532,144825;144948,145153;149575,149785;150358,150562;154352,154649;162235,162435;194413,194613;201540,201740;228125,228325;242360,242560;245940,246380;268008,268214;289382,289586;299434,299692;322829,323030;330360,330565;463496,464961;469069,469832;486758,487642;497968,499013;552948,553562;560170,562393;562404,563017;581787,583642;585509,587594;591214,591513;592041,592651;593134,595017;598166,599489;629291,629812;650827,651368;670174,670659;670669,672979;691391,693804;729093,732000;735012,736000;773029,773514;774815,775457;776001,776482;792582,794626;796577,797558;842117,844752;855037,855521;882839,884135;967811,969215;969235,969602;988178,988349;989130,990324;991569,992000;994964,995578;1034738,1035485;1064682,1067171;1068473,1069163;1093323,1094530;1097884,1099646;1100134,1100570;1158553,1159013;1172964,1174707;1183738,1185707;1194283,1194699;1261416,1261961;1299657,1302856;1316775,1317598;1334311,1336000;1364271,1364720;1385908,1388000;1388533,1389119;1391686,1392000;1430045,1431042;1435101,1435312;1455657,1456925;1458533,1459433;1490408,1491005;1491812,1493448;1500509,1500970;1507291,1508000;1508235,1508522;1509166,1512000;1513521,1518086;1522762,1525905;1539234,1539771;1566234,1567634;1568130,1570667;1581323,1582606;1621847,1622945];
% info.R1059J.FR1.session(2).badsegment = [261,464;1549,1754;3201,3407;20294,20495;22073,22273;22333,22533;25256,25456;26641,26845;27126,27326;27416,27717;27902,28102;28935,29135;33199,33467;33659,34036;34186,34550;34634,34834;35037,35458;35670,35931;36418,36647;37696,37899;38536,38793;41838,43471;43484,43684;43870,44075;44086,45240;45494,45765;46626,46826;46916,47116;47433,47633;47788,48023;48037,54372;54431,54640;54762,55669;56422,56622;56631,57067;57177,57499;59332,59532;62090,62293;64479,64746;64818,65116;65168,65439;65562,65868;66257,66538;66666,67725;74453,74820;75314,75514;89185,89385;100995,101196;136264,136465;153994,154194;159890,160091;165537,165737;194617,194817;205257,205457;216045,216245;242611,243402;244002,244403;244616,246802;247127,247328;251657,252000;270633,271441;279770,282288;315669,315876;337343,338139;362440,363243;364985,366006;372509,373486;382166,382747;411496,412000;438420,439150;451883,452089;456154,458167;469658,470360;540001,540458;593416,594243;614202,614961;673589,674699;681436,682082;732259,732459;752235,753026;755359,755832;761303,763116;782694,783106;785122,785663;793106,793703;815319,818453;824864,825385;835049,835618;839641,840562;868989,869703;878336,881296;887807,890905;942823,947715;948747,950876;994448,995005;997025,997639;1000666,1002368;1021126,1021852;1024989,1025715;1046621,1047017;1060057,1060256;1129557,1130538;1132565,1134937;1137823,1138509;1139617,1140135;1141791,1142376;1154089,1170590;1170883,1172570;1173924,1174417;1183557,1184385;1205045,1205768;1219492,1219731;1225307,1225748;1274347,1275816;1289505,1290215;1291649,1292000;1340537,1341203;1362742,1365514;1403174,1404000;1405138,1405695;1425069,1428000;1469013,1473131;1475407,1476000;1494025,1494739;1546379,1547038;1549327,1550509;1564190,1564861;1608190,1608792;1636166,1636554;1657702,1664000;1700416,1700970;1731186,1732000;1778250,1778884;1800195,1801365;1803722,1806586;1811726,1812224;1888372,1888953;1960533,1961167;1967488,1971094;2048001,2049115;2087710,2088000;2089573,2094957;2110222,2112131;2114682,2115437;2162355,2162556;2202388,2203021;2211105,2211517;2213666,2214622;2239706,2240417;2264001,2266493;2273460,2276522;2301537,2302175;2312001,2312659;2324465,2325159;2392001,2397473;2402257,2402457;2411206,2414417;2470371,2470844;2476525,2477373;2483807,2484381;2504182,2506578;2508952,2509969;2521593,2523469;2551807,2552409;2559504,2560000;2566009,2566679;2596001,2596506;2606819,2608000;2641398,2641605;2654142,2654953;2656001,2656405;2702698,2703058;2710500,2716707;2734045,2734695;2744207,2744965;2771525,2771725;2774584,2774784;2785761,2786137;2786665,2788161];

% Removed some buzz episodes.
info.R1059J.FR1.session(2).badsegment = [261,464;1549,1754;3201,3407;20294,20495;22073,22273;22333,22533;25256,25456;26641,26845;27126,27326;27416,27717;27902,28102;28935,29135;33199,33467;33659,34036;34186,34550;34634,34834;35037,35458;35670,35931;36418,36647;37696,37899;38536,38793;41838,43471;43484,43684;43870,44075;44086,45240;45494,45765;46626,46826;46916,47116;47433,47633;47788,48023;48037,54372;54431,54640;54762,55669;56422,56622;56631,57067;57177,57499;59332,59532;62090,62293;64479,64746;64818,65116;65168,65439;65562,65868;66257,66538;66666,67725;74453,74820;75314,75514;89185,89385;100995,101196;136264,136465;153994,154194;159890,160091;165537,165737;194617,194817;205257,205457;216045,216245;242611,243402;244002,244403;244616,246802;247127,247328;251657,252000;270633,271441;279770,282288;315669,315876;337343,338139;362440,363243;364985,366006;372509,373486;382166,382747;411496,412000;438420,439150;451883,452089;469658,470360;540001,540458;593416,594243;614202,614961;673589,674699;681436,682082;732259,732459;752235,753026;755359,755832;782694,783106;785122,785663;793106,793703;815319,818453;824860,825703;835049,835618;839641,840562;868989,869703;878336,881296;887807,890905;942823,947715;994448,995005;997025,997639;1000666,1002368;1021126,1021852;1024989,1025715;1046621,1047017;1060057,1060256;1129557,1130538;1132565,1134937;1137823,1138509;1139617,1140135;1141791,1142376;1154089,1170590;1170883,1172570;1173924,1174417;1183557,1184385;1205045,1205768;1219492,1219731;1225307,1225748;1274347,1275816;1289505,1290215;1291649,1292000;1340537,1341203;1362742,1365514;1403174,1404000;1405138,1405695;1425069,1428000;1469013,1473131;1475407,1476000;1494025,1494739;1546379,1547038;1549327,1550509;1564190,1564861;1608190,1608792;1636166,1636554;1657702,1664000;1700416,1700970;1731186,1732000;1778250,1778884;1800195,1801365;1803722,1806586;1811726,1812224;1888372,1888953;1960533,1961167;1967488,1971094;2048001,2049115;2087710,2088000;2089573,2094957;2110222,2112131;2114682,2115437;2162355,2162556;2202388,2203021;2211105,2211517;2213666,2214622;2239706,2240417;2264001,2266493;2273460,2276522;2301537,2302175;2312001,2312659;2324465,2325159;2392001,2397473;2402257,2402457;2411206,2414417;2470371,2470844;2476525,2477373;2483807,2484381;2504182,2506578;2508952,2509969;2521593,2523469;2551807,2552409;2559504,2560000;2566009,2566679;2596001,2596506;2606819,2608000;2641398,2641605;2654142,2654953;2656001,2656405;2702698,2703058;2710500,2716707;2734045,2734695;2744207,2744965;2771525,2771725;2774584,2774784;2785761,2786137;2786665,2788161];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1075J %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 99/295 - 0.33559
% 35/262 - 0.13359

% 134/557 - 0.2406

% Kahana: no info
% Me: none

% Overall, very clean. No IEDs. Reliable.
% Just some buzz across channels.
% ROF are spiky, but not removing because LTL.

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

% Line Spectra Info:
% z-thresh 1
info.R1075J.FR1.bsfilt.peak      = [60  120 180 240 300];
info.R1075J.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5 0.5]; 

% line spectra info if L* grid were kept in.
% info.R1075J.FR1.bsfilt.peak      = [60  120 178.7 180 181.4 220 238.7 240 280.1 300 ...
%     100.2 139.8 160.1 260];
% info.R1075J.FR1.bsfilt.halfbandw = [0.5 0.5 0.5   1.7 0.5   0.8 0.5   1.7 0.5   3.1 ...
%     0.5   0.5   0.5   0.5];

% Bad Segment Info:
% info.R1075J.FR1.session(1).badsegment = [114,317;1134,1413;9440,9644;58478,58678;59956,60176;60720,60932;95430,95630;154270,154471;160134,160334;198650,198850;212332,212532;259877,260262;260407,260607;318742,318943;348062,348263;350866,351066;371653,372182;402449,402649;474569,475384;499288,502539;502908,503497;506242,507259;660416,660816;857823,860000;1082839,1084611;1151669,1152454;1273396,1273957;1591274,1594997;1642769,1642969;1774553,1776764;1932001,1933494;1944070,1944703;1945239,1946848;2039172,2039372;2335871,2337510;2361315,2361352;2381138,2386630;2560001,2560635;2866596,2866797];
info.R1075J.FR1.session(2).badsegment = [154,357;1174,1469;36895,37095;50472,50674;167408,167608;170066,170266;178297,178497;199203,199403;200182,200385;202965,203166;209234,209434;240974,241174;265481,265683;277705,277905;281749,281949;313863,314505;366283,366530;371870,373421;398972,399239;407577,408000;579045,579485;591705,591906;696960,697739;753718,754695;756332,756744;848723,849348;852591,852791;856082,857276;886117,889453;947593,948546;1052670,1056000;1183440,1185784;1198605,1199924;1200001,1205268;1216751,1217228;1217811,1218231;1218807,1219078;1269202,1269506;1270504,1270965;1336944,1337961;1375581,1375916;1376001,1376776;1389037,1396498;1438275,1440990;1444444,1447449;1460001,1461026;1489855,1495163;1600001,1601030;1621811,1622864;1842267,1843715;1846654,1848000;1967335,1975114;2040247,2042002;2042456,2042656;2060178,2068000;2125839,2126513;2162766,2164000;2167464,2175775;2185872,2186372;2212134,2215150;2250351,2258497;2304106,2305695;2468352,2469526;2498194,2499521;2528098,2528635;2606254,2607892;2608001,2610461;2625331,2625671;2667359,2667868;2729118,2730006;2741428,2746195];

% Unmarked some buzz episodes.
info.R1075J.FR1.session(1).badsegment = [114,317;1134,1413;9440,9644;58478,58678;59956,60176;60720,60932;95430,95630;154270,154471;160134,160334;198650,198850;212332,212532;259877,260262;260407,260607;318742,318943;348062,348263;350866,351066;371653,372182;402449,402649;474569,475384;502908,503497;506242,507259;660416,660816;1082839,1084611;1273396,1273957;1591274,1592000;1642769,1642969;1774553,1776764;1932001,1933494;1944070,1944703;1945239,1946848;2039172,2039372;2335871,2337510;2361315,2361352;2381138,2386630;2560001,2560635];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1080E %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% Kahana: LTL + MTL
% Me: LTL + MTL

% Clear IEDs + massive buzz
% Some buzz might be remaining.

% 47/175 - 0.26857
% 57/193 - 0.29534

% 104/368 - 0.2826

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

% Line Spectra Info:
info.R1080E.FR1.bsfilt.peak      = [59.9 179.8 239.7 299.7]; % 239.7 is apparent in session 2, but not 1
info.R1080E.FR1.bsfilt.halfbandw = [0.5  0.5   0.5   0.6];

% Bad Segment Info:
info.R1080E.FR1.session(1).badsegment = [239160,239760;412427,416452;430126,432416;560790,560980;563715,565021;568339,572606;608428,611388;869718,869792;874141,875004;877988,878751;879193,882295;957043,957410;968608,968842;994263,997785;1069144,1070928;1098078,1100779;1243373,1246052;1306217,1306621;1316546,1316837;1336276,1337328;1342657,1344128;1360034,1361449;1370750,1371878;1387330,1389651;1408880,1411963;1478521,1479521;1513425,1513583;1513590,1517627;1606550,1606688;1657378,1657753;1658341,1661503;1667364,1668195;1679513,1680847;1682973,1683413;1684194,1686813;1693241,1695699;1699884,1704525;1765725,1766737;1793491,1796119;1849576,1850148;1914617,1917392;1926182,1929433;1962565,1965928;2052180,2056362;2057941,2060624;2084958,2085615;2086553,2088616;2134940,2137003;2138155,2140355;2247485,2251284;2365633,2367491;2368448,2371108;2378044,2381616;2429081,2431648;2480896,2484204];
info.R1080E.FR1.session(2).badsegment = [280893,282336;309485,311688;336966,337309;342214,342690;393969,394369;409792,412057;460423,460811;488910,490095;504653,507159;581350,582833;601729,602197;644166,644590;715378,717433;832450,836519;861195,863448;943822,947658;1039513,1042345;1153382,1155212;1272827,1274463;1373384,1374544;1374625,1376990;1537904,1540359;1591855,1591880;1646776,1647768;1691851,1692956;1693342,1694854;1729595,1730830;1802059,1802766;1927692,1929304];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1120E %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: 

% 'R1120E' - 2    - 13T  - 3F    - 207/600   - 0.3450   - 7T   - 3F    - 207/599  - 0.3456    - :)  - Done. 
% 'R1120E' - 1/2  - 13T  - 3F    - 97/300    - 0.3233   - 7T   - 3F    - 97/300   - 0.3233    
% 'R1120E' - 2/2  - 13T  - 3F    - 110/300   - 0.3667   - 7T   - 3F    - 110/299  - 0.3679    

% When switching to channel labels using individual atlases, channel numbers go to 14T and 4F (vs. 12T and 1F)
% Very clean line spectra.
% Remaining channels very slinky. Not a particularly clean subject.
% Cleaning individual re-ref sessions, baseline too wavy on combined. Same peaks on both sessions. 
% Lots of slinky episodes, some large amplitude episodes.
% Perhaps some ambiguous IED episodes in surfaces. Keeping them in mostly.
% Ambiguous buzz. Mostly leaving them in.
% LPOSTS10 has oscillation with spike atop. Not a T or F channel.
% LANTS5-8 are a little dodgy (spiky). Could take out. [TAKEN OUT]

% Not super for either HFA (buzz) or phase encoding (coverage, IEDs). 

% Channel Info:
info.R1120E.badchan.broken = {
    };
info.R1120E.badchan.epileptic = {'RAMYD1', 'RAMYD2', 'RAMYD3', 'RAMYD4', 'RAMYD5', 'RAHD1', 'RAHD2', 'RAHD3', 'RAHD4', 'RMHD1', 'RMHD2', 'RMHD3' ... % Kahana
    'LPOSTS1', ... % spiky. Confirmed.
    'LANTS10', 'LANTS2', 'LANTS3', 'LANTS4' ... % big fluctuations with one another
    'LANTS5', 'LANTS6', 'LANTS7', 'LANTS8'}; % spikes, especially Session 2

% Line Spectra Info:
% session 2 z-thresh 1 + 2 manual
info.R1120E.FR1.bsfilt.peak      = [60  179.8 299.7 ...
    119.9 239.8]; % manual
info.R1120E.FR1.bsfilt.halfbandw = [0.5 0.5   1 ...
    0.5   0.5]; % manual

% Bad Segment Info:
info.R1120E.FR1.session(1).badsegment = [170475,171499;177831,179269;353469,354723;387613,388601;979690,980806];
info.R1120E.FR1.session(2).badsegment = [334134,334682;432274,434280;438585,439560;1164557,1164646;1380526,1381908;2003415,2003508;2021263,2021976;2318696,2321676;2327103,2329025];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1135E %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1135E' - 4    - 7T   - 15F   - 107/1200  - 0.0892 - 6T - 13F - 31/370   - 0.0838                         - :) - Done. 
% 'R1135E' - 1/4  - 7T   - 15F   - 26/300    - 0.0867 - 6T - 13F - 10/61    - 0.16393                     
% 'R1135E' - 2/4  - 7T   - 15F   - 43/300    - 0.1433 - 6T - 13F - 8/48     - 0.16667                     
% 'R1135E' - 3/4  - 7T   - 15F   - 26/300    - 0.0867 - 6T - 13F - 6/105    - 0.0571436                   
% 'R1135E' - 4/4  - 7T   - 15F   - 12/300    - 0.0400 - 6T - 13F - 7/156    - 0.044872                    

% Frequent interictal events, and lots of channels show bursts of 20Hz activity. 
% RSUPPS grid goes bad in Session 3. 
% Session 3 has lots of reference noise. 
% FR1 was done prior to a re-implant. Localization folder 0 is the same in both releases. This one is presumably the pre-re-implant.
% Line detect on individual re-ref; combo makes wavy baseline.
% An amazing amount of IEDs in RANTTS1-3-5, RPOSTS3. Removal of these would lead to only 2T. Likely to lose more than half of trials.
% Ambiguous IEDs remain.
% Sessions 3 and 4 could probably use a re-clean. Session 1 has been extensively re-cleaned, Session 2 kinda.
% Not bothering to run jumps algorithm. Hardly any buzz, mostly IED. [NOTE: FOUND SPIKY CHANNEL USING JUMPS]
% RANTTS have IEDs, but not being removed b/c these spikes extend to multiple channels. They also get buzzy in Session 3.

% Channel Info:
info.R1135E.badchan.broken = {'RAHCD3', ... Kahana broken
    'RROI1*', 'RROI2*', 'RROI3*', 'RROI4*',  ... Kahana brain lesion
    'LHCD9', 'RPHCD1', 'RPHCD9', 'RSUPPS*' ... mine, 
    };

info.R1135E.badchan.epileptic = { ... % 'RLATPS1' ... % periodic bursts of middling frequency
    'LROI3D7', 'LIPOS3' ... Kahana epileptic
%     'RLATPS3', 'RPOSTS3', 'RLATFS1', ... funky IED-like oscillations
%     'RLATPS7', ... % weirdly discontinuous oscillations
%     'RSUPFS6' ... % spikes on top
    };

% Line Spectra Info:
% Re-referncing prior to peak detection.
info.R1135E.FR1.bsfilt.peak      = [60  119.9 179.8 239.7 299.7];
info.R1135E.FR1.bsfilt.halfbandw = [0.5 0.5   0.5   0.5   0.5];

% Bad Segment Info:
info.R1135E.FR1.session(1).badsegment = [180030,181179;185367,186633;187673,188593;190276,190973;192530,193747;194560,195435;196147,197030;198157,199173;200103,203410;207313,212225;214576,216096;221855,222372;236792,237151;240933,241474;242830,244477;250929,252246;255743,255744;258616,260789;269672,270716;277783,279097;280051,283246;284176,284972;287571,289091;291922,292866;294895,295704;301227,302223;305819,307359;312885,314735;316776,318497;319108,319680;320148,320830;355068,355644;361713,363636;364285,366413;388330,389845;393395,394095;395605,397044;398497,399371;400789,401541;405393,407247;409852,410530;411387,413801;414698,416698;438537,440146;444403,445523;449208,450224;451549,452879;457643,459066;460197,460798;461414,461952;463363,473213;477579,479110;489361,489906;491618,492553;493370,493842;495311,496710;498280,499143;501619,503496;504480,505363;508347,509636;515920,516747;552073,552864;554685,555444;568573,569520;575522,576082;582530,583925;587671,589329;594856,596586;597451,599400;603687,604236;606721,607756;609020,610124;611389,612800;613326,616220;644320,647115;650102,650942;651788,652478;654367,654954;655842,657317;661246,664288;674212,674938;688910,690286;691103,693066;700783,702777;704086,705449;706273,706939;708256,710629;711486,714077;717717,718935;731438,732756;757492,758645;760099,762891;765698,766452;772369,773014;776047,777991;786640,787212;791209,794541;800651,801417;802266,803196;806415,807192;808764,809630;811189,815855;818910,819180;820639,822833;824131,825208;826165,826649;828071,829323;852917,853780;864418,865474;866911,868443;871129,871684;883963,884588;887113,895104;900152,901667;907476,908367;909997,912653;915552,916238;918319,919583;920201,920874;924390,925402;938685,939060;941985,943056;963271,964609;971581,972061;972491,975401;978509,982409;991009,993451;1001208,1001732;1005925,1006992;1012596,1014059;1014985,1017048;1018134,1019512;1021361,1021966;1022977,1024605;1025792,1026972;1027001,1028718;1031899,1032835;1034094,1034964;1050949,1051751;1057285,1057793;1059815,1060927;1064983,1066932;1068834,1070928;1073184,1074418;1076407,1078067;1078646,1081789;1082917,1084436;1090207,1091492;1095563,1096553;1098082,1099546;1100363,1101101;1102556,1104867;1105229,1106301;1109839,1110440;1112641,1114313;1118881,1119683;1122465,1125655;1128858,1130466;1142857,1143861;1148250,1149085;1159135,1160175;1161487,1162237;1164577,1167100;1170325,1171869;1173181,1173850;1178821,1179611;1182817,1185073;1200182,1202652;1207651,1209553;1252614,1252989;1265004,1266530;1269037,1269605;1270559,1272462;1284018,1285420;1286261,1286712;1292219,1292510;1294914,1296502;1298701,1300297;1303668,1305469;1311696,1312806;1313963,1314684;1315297,1318552;1320683,1321920;1323176,1325984;1337126,1337884;1359334,1360684;1370080,1371226;1374113,1375903;1381545,1383244;1392176,1392873;1399950,1401115;1404643,1405103;1410256,1411520;1419765,1422576;1426395,1427154;1428115,1428684;1431705,1432104;1459785,1460854;1466533,1467428;1473296,1474030;1478021,1478786;1479582,1481772;1482435,1484516;1494045,1494784;1496414,1497708;1498706,1499533;1502186,1504789;1506493,1509784;1510489,1511312;1513491,1514484;1517763,1521257;1523041,1524546;1530323,1531553;1551363,1552023;1553419,1554444;1557326,1560617;1563307,1564206;1565689,1566432;1569345,1570095;1571361,1572216;1578233,1580240;1582114,1582640;1595458,1596085;1598566,1610123;1610389,1611171;1615891,1616623;1619589,1622376;1626814,1628573;1630977,1631836;1649728,1650894;1652971,1653443;1658709,1659752;1661200,1662336;1662353,1663023;1665750,1667135;1670329,1671526;1689442,1690308;1690913,1691673;1693825,1695420;1700162,1700835;1725787,1726977;1728484,1729874;1730829,1732284;1736085,1737528;1738212,1742548;1743513,1746252;1747638,1748821;1750249,1751245;1759308,1760723;1765139,1766232;1767723,1768662;1772178,1773705;1780964,1782216;1786624,1788346;1791570,1792473;1795091,1795966;1797531,1798200;1798676,1799895;1802777,1803221;1816535,1817448;1818644,1819338;1839995,1841150;1842157,1843580;1844626,1845289;1845890,1847487;1852972,1853839;1858568,1859622;1862856,1863523;1870346,1871395;1876074,1876788;1885687,1887995;1896030,1897694;1898101,1899290;1904572,1906092;1907680,1908772;1911426,1912782;1920864,1921533;1928018,1928966;1932002,1933074;1935913,1936736;1948417,1949095;1952276,1954044;1968196,1970028;2005993,2008676;2036301,2037176;2045586,2045952;2048391,2049049;2050209,2051194;2061344,2062363;2072500,2073924;2074930,2075787;2081917,2084918;2087796,2088467;2095963,2097482;2099127,2099769;2101328,2103453;2104780,2106188;2117913,2118700;2135190,2136045;2137034,2139976;2142457,2143028;2146751,2148572;2154397,2156226;2160886,2161620;2162385,2165402;2168072,2169483;2179045,2179779;2184854,2185438;2193431,2194050;2195106,2197338;2208026,2209788;2214518,2216404;2222099,2223131;2247666,2249431;2250583,2251490;2252471,2253744;2257993,2258562;2263408,2276030;2280693,2282421;2286456,2288481;2296645,2297700;2299145,2300193;2301697,2302630;2305693,2306812;2308730,2310773;2312673,2317680;2319272,2321676;2333269,2333664;2354398,2356950;2357382,2358637;2363224,2364848;2367852,2368457;2372819,2373624;2377109,2377781;2400191,2401596;2406604,2407362;2409589,2410343;2442801,2442915;2480094,2481516;2503776,2504261;2506862,2507439;2539829,2540825;2600361,2601230;2608158,2609053;2616164,2617380;2665369,2665924;2672853,2676328;2679319,2680862;2694155,2695642;2699766,2700935;2701297,2703380;2707754,2708548;2712827,2713608;2717545,2718706;2719909,2721276;2721285,2722124;2723262,2724403;2728610,2729176;2749412,2750605;2752507,2753144;2757843,2758875;2760483,2762126;2764676,2769228;2770570,2773947;2776356,2777220;2784705,2785212;2786917,2788569;2792902,2796186;2797201,2798708;2801197,2803000;2804455,2805192;2808415,2808931;2810868,2811417;2814152,2815381;2817181,2819324;2820512,2821176;2823179,2824827;2825403,2826120;2842204,2843045;2846196,2846860;2855467,2856275;2858555,2861136;2869638,2873124;2873459,2874902;2875807,2877786;2878671,2879339;2882281,2882987;2886442,2891740;2891936,2892585;2896045,2897100;2899908,2902010;2903276,2904400;2905286,2905787;2906827,2908604;2909089,2910596;2912774,2913084;2914128,2919136;2922676,2924247;2925073,2926492;2927683,2928940];
info.R1135E.FR1.session(2).badsegment = [155845,158291;161027,163309;164594,165094;166004,168795;170036,170713;174998,177632;181700,182865;184045,185896;187972,189568;190090,190748;191625,192857;197492,199128;208451,209763;214022,215010;217452,218533;222568,223776;225444,228557;230906,235764;238020,243756;247753,250311;253807,258964;260160,261337;263345,263736;264349,266146;274474,275405;278206,279960;283878,284729;286168,296368;325147,325698;328511,329919;334651,339660;340692,341311;342361,356159;358106,358453;361667,363636;367633,368705;369514,370034;372016,372721;381401,382385;386619,387948;390347,391608;393327,395604;400561,401541;402311,402860;422432,423045;433047,434927;440207,441276;444119,447552;448620,449950;452749,454041;456407,457650;459541,463536;468067,471528;480302,487512;489515,490581;494356,495993;498397,498941;500461,503496;530437,531468;537563,542889;547453,549254;553157,554410;556689,557919;561120,562027;563965,566994;575425,576227;583417,584505;590683,591408;593094,594414;600404,601897;605403,605969;609660,610636;612986,613720;640775,641567;647772,648480;651231,654966;656573,658536;659667,661517;663981,664888;668094,670499;671329,672387;674225,674707;675325,676317;685931,687312;688187,691308;693379,694634;695305,697948;700296,707076;708251,710099;712525,713855;718052,719280;753899,755244;761456,763236;764461,765562;774773,777064;779497,780487;783081,783641;787680,791208;794008,797731;799201,799762;801134,802706;803853,804815;807193,808616;810495,811188;812037,813127;815362,816181;818950,820471;821972,823064;827769,828362;848089,848707;860345,860990;865501,866418;868585,869379;870923,872701;878701,879440;880583,882153;887290,888954;889634,890219;892827,894050;896450,898139;901127,901784;902810,910010;910939,911485;913924,915859;917838,919517;921811,923076;925570,927072;964386,965011;966388,966807;968881,971636;974037,974763;975025,975805;977590,978840;981804,982477;987359,991864;1011468,1014325;1015694,1017201;1021148,1022441;1025885,1026550;1027589,1029717;1036270,1036996;1039541,1040065;1042179,1042956;1059867,1061817;1072685,1073318;1078731,1079305;1081974,1082916;1085869,1087268;1090674,1093610;1094687,1096352;1098485,1098900;1101261,1102337;1103658,1104239;1107688,1110888;1113474,1114884;1119995,1122876;1124991,1126265;1127747,1130313;1132399,1134309;1137036,1137584;1140057,1148247;1186813,1188721;1191186,1198604;1198801,1201224;1203244,1205752;1207337,1209390;1210789,1211569;1226349,1226772;1235570,1237609;1238761,1239964;1243158,1245668;1248098,1248816;1250039,1250656;1251047,1253746;1260320,1262736;1276569,1277326;1278721,1279419;1297588,1301916;1302611,1303270;1305568,1310688;1311615,1317743;1318681,1319334;1323289,1323906;1326100,1326672;1355136,1356519;1394605,1395250;1399020,1400150;1401241,1402596;1405549,1406090;1436961,1438170;1444901,1446552;1449002,1449679;1451822,1453013;1455959,1457103;1457263,1458513;1461155,1462536;1476547,1477260;1478521,1480024;1481630,1482516;1484567,1486512;1487661,1488606;1490509,1494504;1498501,1501353;1506896,1512761;1522815,1523384;1528632,1529398;1544064,1544981;1546453,1549817;1553552,1554444;1555766,1557136;1564565,1569338;1570836,1571376;1576837,1577807;1586413,1588524;1589784,1590408;1591525,1593503;1594643,1595381;1596543,1597819;1599627,1600790;1606393,1609302;1611082,1615441;1650550,1651103;1657148,1657824;1660119,1661413;1664222,1664873;1666123,1666660;1667412,1668489;1669885,1670328;1672395,1675248;1676778,1678320;1682941,1683653;1684971,1685653;1689257,1690308;1692633,1693709;1696037,1698300;1699767,1700491;1707392,1708471;1709793,1710288;1711860,1714556;1719920,1720930;1722277,1724674;1740194,1741266;1742623,1743269;1749382,1749991;1751373,1751800;1754245,1757234;1758901,1760332;1762237,1765607;1767715,1771744;1773608,1774140;1775204,1777609;1786982,1788226;1789727,1790838;1792801,1794204;1794978,1795495;1796448,1797814;1799401,1801295;1802777,1805110;1806568,1807134;1810085,1811211;1812853,1814184;1815786,1820665;1822177,1823763;1824950,1826172;1830989,1832031;1858658,1862388;1869915,1871415;1873053,1875519;1877113,1879826;1886620,1888170;1891128,1893545;1897327,1900992;1903229,1903872;1909244,1910088;1912747,1917356;1918081,1920829;1922077,1925715;1948828,1950048;1957327,1958040;1959628,1960752;1963483,1965618;1967052,1967655;1968693,1970028;1971873,1973832;1979998,1980624;1989553,1990244;1992160,1993643;1996854,1998000;2001997,2002667;2005993,2006679;2016097,2016906;2018839,2019537;2021098,2021976;2042235,2044568;2044621,2045952;2059959,2060610;2066827,2068568;2079435,2081027;2083701,2084661;2087637,2088479;2093905,2095682;2105507,2107320;2110113,2112200;2114137,2114794;2124160,2124677;2126815,2129005;2136036,2136576;2145853,2147463;2157978,2158547;2180547,2182249;2183672,2184935;2185813,2186456;2189809,2193056;2194228,2197800;2215740,2216819;2235893,2237038;2238999,2239576;2259885,2260418;2280822,2281716;2284651,2285712;2287892,2288632;2290458,2293704;2294587,2295256;2297007,2297700;2300564,2302741;2305693,2309688;2322786,2324123;2326837,2327490;2335779,2337023;2338718,2339839;2347669,2348423;2352778,2353644;2355554,2356769;2359558,2360175;2361774,2362256;2377270,2378262;2380376,2381212;2395027,2395829;2404134,2405233;2405891,2407173;2408416,2409588;2411139,2413584;2414338,2417184;2419148,2420256;2433565,2434216;2442391,2444697;2445553,2446454;2453012,2454243;2456775,2457540;2468940,2469528;2506149,2508800;2516679,2519351;2521477,2524225;2543734,2544352;2547422,2548863;2553445,2556319;2557920,2558630;2563402,2565133;2568161,2569428;2574428,2575085;2581755,2582399;2602893,2604457;2608281,2608974;2612264,2614135;2619175,2619746;2622239,2625372;2626517,2627468;2629239,2630778;2634648,2637360;2641663,2648523;2653247,2655889;2659371,2661336;2662759,2664787;2665512,2666609;2668506,2668918;2669603,2670788;2674126,2675366;2676353,2677320;2700265,2700999;2702646,2704274;2707001,2709288;2722646,2727195;2728732,2729268;2730501,2732564;2736289,2737046;2741873,2743008;2744292,2745252;2746161,2747785;2748563,2748959;2749249,2750351;2761978,2762664;2764096,2765232;2770689,2773456;2787464,2788049;2802554,2802990;2804620,2805192;2808604,2809188];
info.R1135E.FR1.session(3).badsegment = [243757,244962;253312,253913;256087,259740;260877,263736;266572,269248;270673,273285;277034,278497;291084,291556;308225,308689;311481,316995;318029,319680;320970,321543;322101,322489;324994,325563;326536,327672;336744,337349;338637,339158;340732,342247;347028,347652;349046,350920;353703,355214;359282,360971;363024,365003;365933,367375;369639,370256;372000,372528;375358,376637;402972,403596;405107,405749;415157,416025;419391,423576;427016,429048;438279,440363;442449,442925;444221,447552;448805,451388;451549,453249;454006,454546;457933,459279;460536,461052;474847,475412;478940,479400;511303,512755;515013,515484;515960,518426;519787,520304;522236,522829;523477,525629;526888,528590;530501,532042;533624,539460;556061,556541;566973,567344;570087,570350;573366,575115;577718,579420;581185,582571;583868,586233;611687,612675;617080,618608;620770,622338;623957,624852;627788,628965;650301,650878;651905,654161;657761,660542;672851,673299;689882,690415;697145,698576;706019,710290;711071,712071;713593,716692;733995,734548;735265,736293;745722,747252;753750,754854;755245,756418;757677,759240;774012,776559;777653,778524;796606,797683;800828,801353;826018,826682;830306,831101;831181,833349;838091,838585;845444,845937;850218,850766;866790,867311;875661,876294;883117,884751;916599,916910;917960,919080;923294,923859;925155,926751;929485,930135;932406,933631;937828,939396;942770,943056;944881,945499;951262,954139;961739,962771;965361,966139;967255,968343;982029,982526;985965,988222;989433,990542;1026973,1027522;1029047,1029636;1032012,1033060;1043448,1047302;1053180,1054944;1057023,1057538;1066473,1067047;1068415,1069145;1082030,1087413;1089901,1091647;1120665,1121145;1122877,1123998;1127791,1129319;1131650,1133057;1138457,1139615;1145148,1145774;1149724,1150848;1151441,1152707;1154031,1154519;1216182,1218016;1219925,1221206;1222639,1223116;1274890,1276639;1313693,1315544;1318681,1321723;1335523,1337791;1381170,1383315;1389066,1390608;1392272,1395665;1424868,1425357;1446117,1446552;1450549,1451198;1467451,1468793;1471230,1471863;1486371,1486824;1490763,1491807;1493211,1494504;1496684,1497969;1503306,1507593;1543701,1544282;1545779,1546292;1546876,1547517;1548253,1548846;1550359,1550943;1551524,1551980;1554932,1556141;1558441,1559308;1562437,1580995;1583424,1584009;1593240,1593765;1594405,1594817;1595649,1596069;1597297,1597886;1601905,1602396;1606627,1607058;1609426,1610002;1615186,1617237;1625550,1625954;1626957,1628001;1641506,1642356;1649414,1650075;1651054,1656154;1665188,1665681;1678490,1679148;1681261,1681870;1686159,1686749;1710289,1710942;1713064,1713616;1726099,1726934;1727521,1728296;1739427,1741403;1742257,1747466;1750913,1757077;1761491,1762236;1763300,1764989;1772504,1773158;1777741,1779406;1780436,1781226;1785705,1786212;1787127,1789359;1791341,1793371;1794051,1798200;1798656,1800546;1801813,1804856;1824658,1825174;1848581,1850148;1855981,1858069;1858141,1859737;1860211,1861920;1862987,1864796;1865685,1867290;1882596,1883673;1892554,1893122;1894363,1895669;1944506,1946231;1954045,1955669;1962283,1963907;1967205,1967721;1983205,1983778;2006351,2008600;2018782,2020378;2039580,2041462;2064486,2065932;2070714,2072141;2074710,2075336;2087274,2088254;2092797,2093390;2094155,2094663;2100970,2101494;2102960,2103692;2107893,2109317;2110924,2111432;2116104,2117880;2122759,2123159;2146292,2147340;2149849,2151106;2155496,2157785;2158409,2158817;2160020,2160633;2162397,2164693;2166594,2168335;2186272,2187058;2192886,2193290;2196616,2197406;2210961,2212742;2215633,2220665;2243388,2243884;2246309,2247077;2256238,2257740;2259859,2260255;2260999,2261697;2263203,2265242;2285713,2288150;2290877,2291454;2294591,2295168;2301697,2305692;2307413,2307869;2309535,2311245;2314716,2318121;2365350,2366045;2369629,2370117;2388996,2393604;2399524,2400006;2405137,2405592;2406793,2407265;2408976,2409588;2411727,2412288;2413585,2414150;2415796,2417580;2423651,2424796;2451253,2452591;2455410,2456792;2459486,2461536;2467965,2468542;2469419,2470033;2471772,2473524;2476493,2479447;2507946,2508937;2510319,2510908;2513174,2513484;2529469,2530328;2562202,2562598;2563962,2564507;2567141,2568434;2580723,2581416;2583237,2584016;2602984,2605392;2608067,2609388;2611624,2612116;2618577,2619613;2623914,2624358;2629369,2630441;2653247,2653773;2659669,2661336;2671826,2672455;2679721,2680346;2682199,2682780;2699621,2700963;2703882,2704798;2706147,2706981;2707701,2708572;2716982,2717564;2722850,2724041;2726046,2726885;2728257,2728834;2763875,2765232;2771537,2772963;2776926,2778374;2779786,2781116;2786993,2789208;2806864,2807502;2808709,2810297;2811903,2813184;2815174,2816025;2816725,2817180;2819090,2820339;2832234,2835900;2859312,2859872;2863529,2864561;2866458,2867317;2886345,2886870;2889745,2890326;2905238,2905750;2913721,2914165;2915803,2916364;2920291,2921493;2924303,2925751;2927147,2927647;2933065,2933505;2963562,2964719;2967026,2967495;2975284,2977944;2989988,2990846;2995244,2995849;3008662,3009393;3010958,3011463;3011977,3012984;3013565,3013892;3018620,3020976;3023208,3023656;3032965,3033494;3035204,3039467;3047490,3048087];
info.R1135E.FR1.session(4).badsegment = [147938,151829;157275,159084;161162,162891;163711,164092;203341,203796;206910,207527;238443,240769;249318,249824;254173,255415;263737,264117;265316,265961;276273,276854;278681,279463;280309,280866;310480,310880;325030,325418;333473,334602;343233,343815;344684,350960;359641,362091;367951,369253;370545,371259;372632,374312;381425,382510;387613,389539;408729,409245;422662,423239;427573,429608;431057,431568;432610,433370;434952,438949;442175,442852;445583,450099;456536,459540;477313,477850;479521,486357;517374,529033;537825,545214;551993,552453;556770,557411;558627,559095;559441,561206;563114,566128;568565,570430;580335,582100;585882,587412;587844,590153;604778,606402;619405,620123;623050,623942;625443,625806;627828,629235;631663,632320;635812,638491;638808,639360;660706,663336;664300,664836;716191,717284;731704,732200;736095,737960;739386,739979;745617,746194;747994,748925;751378,753437;767233,767705;770394,770915;828723,831702;835165,838102;843366,847525;918762,919080;919596,921096;932535,933647;985590,988512;991190,992383;1039690,1040601;1044093,1046952;1051412,1056557;1061168,1062936;1069808,1070486;1073470,1074091;1077104,1078920;1079171,1079566;1086469,1087466;1095010,1095599;1101303,1102896;1102994,1104046;1105760,1106892;1142917,1143456;1151644,1152284;1155199,1155825;1157716,1161919;1166379,1166832;1168134,1169850;1176114,1177919;1183864,1184441;1196009,1196554;1198051,1198559;1211832,1212759;1250079,1250748;1251530,1253956;1259840,1262736;1266846,1267511;1285580,1286202;1286615,1287121;1288191,1290383;1293234,1293710;1295994,1297956;1343410,1344204;1347591,1348273;1349122,1349735;1351950,1352841;1354794,1355460;1374149,1376285;1378201,1378620;1381931,1382616;1404224,1405000;1414786,1415246;1418193,1418799;1419821,1424926;1438690,1439202;1448361,1449570;1450549,1452620;1454214,1456185;1458702,1466532;1468619,1470528;1470827,1471847;1474996,1476858;1489799,1490288;1492680,1493466;1495270,1496431;1507911,1508387;1511335,1514179;1519909,1520902;1554090,1555574;1558578,1559586;1562691,1564762;1567444,1569797;1570542,1571231;1590409,1592971;1604926,1608790;1612056,1612661;1617289,1617898;1618570,1619292;1646353,1648561;1655654,1657076;1662337,1662954;1667275,1668690;1681708,1682316;1698139,1699405;1719803,1720280;1754245,1755349;1762006,1764598;1776907,1777569;1778547,1779672;1791457,1791942;1792935,1793698;1819433,1820175;1821149,1821794;1822177,1822710;1849637,1851000;1858435,1859121;1860722,1861420;1862137,1863117;1866657,1868212;1882653,1883137;1894274,1894634;1901053,1901634;1902931,1903576;1904912,1906092;1907905,1909461;1911974,1912567;1916819,1917372;1918935,1919492;1925867,1926304;1948361,1949316;1952131,1954044;1962242,1962856;1989126,1991174;2002951,2003657;2005291,2007573;2026855,2027375;2047661,2049208;2054607,2055843;2060583,2060981;2078396,2078852;2088261,2089144;2090441,2092886;2093654,2094144;2099387,2099920;2104172,2104922;2106856,2107267;2110533,2111843;2117175,2117700;2119335,2119944;2142070,2142847;2144209,2144810;2150159,2151243;2153845,2154998;2157723,2159177;2160958,2161535;2162920,2164995;2168745,2169414;2170308,2170720;2172773,2173334;2196258,2196532;2203070,2203483;2205164,2205792;2220302,2222036;2260411,2261048;2262977,2264613;2269789,2270360;2278982,2279583;2303860,2311273;2314821,2315369;2320669,2321323;2322124,2322689;2326648,2329166;2358986,2361636;2361951,2362814;2370032,2372546;2373625,2380719;2395453,2395881;2396992,2397600;2402253,2403146;2420030,2420594;2422088,2422738;2424465,2424937;2468654,2471370;2473887,2474392;2481960,2483282;2495901,2497500;2499825,2500724;2508127,2508744;2518162,2521937;2523974,2524800;2526230,2526743;2547060,2547532;2555817,2556342;2563253,2563935;2564679,2566936;2573614,2574207;2577421,2578666;2581590,2584918;2586698,2587160;2613104,2613742;2624675,2625252];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1142N %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1142N' - 1    - 19T  - 60F   - 48/300  - 0.1600   - 18T  - 57F   - 37/194 - 0.19072   - :) - Done. 

% Kahana: LPFC + MPFC
% Me: no additional

% Diffuse, ambiguous IEDs

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

% Line Spectra Info:
% Session 1/1 eyeballing
info.R1142N.FR1.bsfilt.peak      = [60  120 180 240 300];
info.R1142N.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5 0.5];

% Bad Segment Info:
% info.R1142N.FR1.session(1).badsegment = [1,1915;2978,3154;6479,7036;7459,7503;8360,8401;8840,8865;12299,12341;13166,13211;15373,15544;16498,17176;20396,21061;23583,23995;25506,26211;29605,30170;32562,33144;33417,33998;35838,35877;36151,36762;38320,39641;44001,44776;45968,46098;46986,47041;48001,48703;50210,50275;50938,51401;53054,53566;54376,55014;57495,58176;58629,59114;60122,60381;61903,62630;63349,64137;64458,64502;66374,66437;74591,75168;81675,81722;82156,82219;82250,82281;82629,82665;83172,83235;83855,83904;83981,84016;84605,84631;85033,85066;86548,86638;87802,88711;88955,88996;89516,89558;91976,92004;92535,92596;92828,92889;103419,104000;104186,104227;104802,104840;105183,105254;105339,105450;105530,105558;109885,110514;112261,112287;112640,112674;112707,112746;115328,115439;118556,118582;119072,119103;120933,121587;122605,122630;122750,122778;122882,122998;123336,123369;125143,125187;130180,130213;130608,130649;130718,130759;133465,133499;133605,134281;134565,134622;135349,135399;136001,137079;137404,137439;137793,137883;139906,139950;142218,142867;159712,159772;160001,160749;161562,162047;162280,162342;162403,162482;162661,162781;162852,162896;163223,163920;165025,165544;165559,165611;167782,168518;169425,170047;170680,171718;172001,173184;173793,174953;175508,177219;177734,178058;180001,197372;198927,200000;202540,215995;216001,232000;233000,236000;240525,240905;241557,241888;242731,243254;244001,244321;244323,249982;252057,252101;253428,253482;254680,254719;255140,255176;255717,255864;256135,256988;258586,259853;261782,262713;264624,265246;266651,266695;268850,269370;270046,270084;270532,270969;272275,272692;273331,273372;278573,278619;280267,280754;284001,284504;285484,285512;286180,286222;287099,287143;287309,287393;288780,288819;291787,291837;297928,298587;312952,313840;314470,314850;315615,315659;316226,317047;318137,318313;318978,319643;320052,320719;321559,321601;333694,333719;334199,334375;334438,334471;334890,334928;335551,336000;336323,336800;345495,346168;347148,347705;372092,372735;376001,376574;377551,377571;380001,380980;383083,383122;384170,384803;386796,386834;389839,390434;392619,393577;398532,400000;418532,419073;420001,420571;432952,433509;433573,433603;437917,438547;439314,440000;442667,443383;450556,451079;457831,458283;459699,460287;468001,469512;478309,479374;480001,480641;481430,482380;485140,486160;490922,491538;510836,511458;514100,514160;515301,516000;518866,520000;522264,523667;525648,525711;530968,531452;536885,537644;541895,542297;545879,546488;576901,577574;587341,587377;602935,602966;616140,616768;632001,632663;648718,649241;652363,652545;659137,659826;669398,669896;670556,670939;674796,675213;705288,705802;707771,708000;709054,709547;712001,712383;712705,712760;734497,734912;737390,738101;742341,743087;747091,747692;748291,749104;761995,762727;789191,789792;822952,824000;832001,832582;834393,835606;836401,837015;838387,838936;855519,855987;857745,858222;858857,859423;892130,892905;901189,901945;915527,916000;918067,918600;920896,920964;929146,929633;932221,932800;934414,935108;948726,949241;968511,969149;972949,973364;1000474,1000966;1002382,1002842;1005796,1007049;1017019,1018246;1025008,1025910;1032879,1033534;1035505,1035915;1037519,1039211;1048425,1049023;1053245,1054076;1057522,1057998;1060154,1060214;1065968,1066633;1071134,1071557;1072487,1073265;1077911,1078469;1091188,1091305;1101893,1102466;1127602,1128000;1130195,1130698;1131678,1132310;1133393,1134032;1136342,1136860;1137068,1137754;1143616,1144780;1153202,1153829;1159075,1159761;1167376,1168000;1175513,1176000;1193116,1193813;1230852,1231630;1248272,1248840;1254274,1255197;1266855,1267721;1286624,1287151;1294847,1296000;1313070,1313783;1332001,1332510;1376581,1377343;1380054,1380596;1393847,1394504;1397162,1397877;1410396,1411138;1429003,1429617;1441113,1441708;1477549,1478630;1509035,1509544;1514003,1514547;1526827,1527400;1527468,1528000;1535659,1536257;1547263,1547737;1549368,1550114;1576001,1576590;1584001,1584913;1588699,1589302;1592646,1593421;1595355,1596101;1598823,1599731;1604296,1604800;1614307,1614832;1622113,1622784;1629960,1630590;1642312,1642721;1707301,1707864;1712888,1713659;1716159,1716692;1745884,1746582;1749819,1750679;1771218,1771619;1819505,1820000;1835255,1836000;1855266,1856000;1860885,1861558;1863653,1864000;1865988,1866888;1880269,1880864;1891834,1892628;1901237,1901848;1925988,1927586;1961106,1962788;1964659,1965235;1975700,1976268;1981775,1982546;1985301,1985802;2027149,2027937;2031864,2032640;2066791,2068485;2095193,2095979;2099331,2100579;2108052,2108437;2116848,2119009;2121581,2122449;2144724,2145184;2179069,2179767;2192001,2192812;2236461,2237292;2252449,2253052;2255307,2256389;2262427,2263036;2264001,2264667;2266226,2266824;2306785,2307404;2312398,2312907;2336987,2337515;2344311,2345026;2351296,2352518;2355654,2356188;2371766,2372433;2385009,2386413;2387567,2388000;2406914,2407356;2429782,2430345;2432759,2433469;2443825,2444716;2449178,2449759;2450237,2450885;2456001,2456808;2527072,2527571;2554710,2555533;2556001,2564000;2568001,2568708;2584066,2586457;2606444,2607006;2620573,2621141;2669646,2671187;2673086,2673727;2676251,2678534;2697001,2697280;2724001,2724448;2725392,2726102;2752995,2753566;2754621,2755149;2772001,2772848;2785809,2787033;2793807,2794369;2816569,2820000;2852324,2852941;2873785,2874380;2924001,2932000;2932291,2932867;2943424,2943787;2944094,2944913;2946527,2949077;2955790,2956611;2966100,2967340;2972001,2972657;2981253,2981843;2985116,2985902;3000304,3000843;3002170,3006223;3009404,3009514;3018073,3018872;3020748,3021310;3035046,3037259;3047132,3047767;3056001,3056499;3060001,3061052;3068490,3069036;3107661,3109211;3196589,3196918;3197328,3197835;3204001,3204674;3221121,3221687;3233718,3234380;3239207,3240000;3254208,3261587;3280576,3281101;3288505,3289240;3300850,3301507;3313033,3313776;3355807,3356511;3364271,3365042;3365404,3366110;3408904,3409719;3435929,3436469;3456001,3457506;3468670,3469417;3471367,3472000;3474538,3475181;3478738,3479312;3497589,3498856;3547295,3548000;3600719,3601631;3603085,3604389;3619841,3620191;3621440,3622268;3671296,3671780;3673605,3682800;3686745,3687240;3688643,3689101;3696001,3696434;3705561,3706610;3754239,3755364;3764057,3764706;3765127,3765730;3767244,3767791;3769654,3770763;3784190,3785002;3793215,3793757;3812815,3813643;3828108,3828633;3831726,3832474;3861283,3861942;3894694,3895388;3911081,3911767;3965315,3965981;4004296,4004948;4013213,4013797;4021011,4021746;4024997,4025796;4026787,4027469;4034831,4035457;4036614,4038679;4062667,4063254;4116444,4118042;4118368,4118842;4121597,4122149;4123340,4124357;4174954,4175466;4176651,4177257;4200070,4201054;4209129,4209679;4212440,4213082;4227745,4228411;4234680,4235245];

% Unmarking swoops without initial synchronous spike
info.R1142N.FR1.session(1).badsegment = [1,1915;2978,3154;6479,7036;7459,7503;8360,8401;8840,8865;12299,12341;13166,13211;15373,15544;16498,17176;20396,21061;23583,23995;25506,26211;29605,30170;32562,33144;33417,33998;35838,35877;36151,36762;38320,39641;44001,44776;45968,46098;46986,47041;48001,48703;50210,50275;50938,51401;53054,53566;54376,55014;57495,58176;58629,59114;60122,60381;61903,62630;63349,64137;64458,64502;66374,66437;74591,75168;81675,81722;82156,82219;82250,82281;82629,82665;83172,83235;83855,83904;83981,84016;84605,84631;85033,85066;86548,86638;87802,88711;88955,88996;89516,89558;91976,92004;92535,92596;92828,92889;103419,104000;104186,104227;104802,104840;105183,105254;105339,105450;105530,105558;109885,110514;112261,112287;112640,112674;112707,112746;115328,115439;118556,118582;119072,119103;120933,121587;122605,122630;122750,122778;122882,122998;123336,123369;125143,125187;130180,130213;130608,130649;130718,130759;133465,133499;133605,134281;134565,134622;135349,135399;136001,137079;137404,137439;137793,137883;139906,139950;142218,142867;159712,159772;160001,160749;161562,162047;162280,162342;162403,162482;162661,162781;162852,162896;163223,163920;165025,165544;165559,165611;167782,168518;169425,170047;170680,171718;172001,173184;173793,174953;175508,177219;177734,178058;180001,197372;198927,200000;202540,215995;216001,232000;233000,236000;240525,240905;241557,241888;242731,243254;244001,244321;244323,249982;252057,252101;253428,253482;254680,254719;255140,255176;255717,255864;256135,256988;258586,259853;261782,262713;264624,265246;266651,266695;268850,269370;270046,270084;270532,270969;272275,272692;273331,273372;278573,278619;280267,280754;284001,284504;285484,285512;286180,286222;287099,287143;287309,287393;288780,288819;291787,291837;297928,298587;312952,313840;314470,314850;315615,315659;316226,317047;318137,318313;318978,319643;320052,320719;321559,321601;333694,333719;334199,334375;334438,334471;334890,334928;335551,336000;336323,336800;345495,346168;347148,347705;372092,372735;376001,376574;377551,377571;380001,380980;383083,383122;384170,384803;386796,386834;389839,390434;392619,393577;398532,400000;418532,419073;420001,420571;432952,433509;433573,433603;437917,438547;439314,440000;442667,443383;450556,451079;457831,458283;459699,460287;468001,469512;478309,479374;480001,480641;481430,482380;485140,486160;490922,491538;510836,511458;514100,514160;515301,516000;518866,520000;522264,523667;525648,525711;530968,531452;536885,537644;541895,542297;545879,546488;576901,577574;587341,587377;602935,602966;616140,616768;632001,632663;648718,649241;652363,652545;659137,659826;669398,669896;670556,670939;674796,675213;705288,705802;707771,708000;709054,709547;712001,712383;712705,712760;734497,734912;737390,738101;742341,743087;747091,747692;748291,749104;761995,762727;789191,789792;822952,824000;832001,832582;834393,835606;836401,837015;838387,838936;855519,855987;857745,858222;858857,859423;892130,892905;901189,901945;915527,916000;918067,918600;920896,920964;929146,929633;932221,932800;934414,935108;948726,949241;968511,969149;972949,973364;1000474,1000966;1002382,1002842;1005796,1007049;1017019,1018246;1025008,1025910;1032879,1033534;1035505,1035915;1037519,1039211;1048425,1049023;1053245,1054076;1057522,1057998;1060154,1060214;1065968,1066633;1071134,1071557;1072487,1073265;1077911,1078469;1091188,1091305;1101893,1102466;1127602,1128000;1130195,1130698;1131678,1132310;1133393,1134032;1136342,1136860;1137068,1137754;1143616,1144780;1153202,1153829;1159075,1159761;1167376,1168000;1175513,1176000;1193116,1193813;1230852,1231630;1248272,1248840;1254274,1255197;1266855,1267721;1286624,1287151;1313070,1313783;1331837,1332607;1376581,1377343;1380054,1380596;1397162,1397877;1458287,1458876;1477549,1478630;1526799,1528000;1535659,1536257;1576001,1576590;1588699,1589302;1595355,1596101;1598823,1599731;1604296,1604800;1614307,1614832;1622113,1622784;1629960,1630590;1716159,1716692;1745884,1746582;1749819,1750679;1835255,1836000;1855266,1856000;1860885,1861558;1891834,1892628;1901237,1901848;1925988,1927586;1964659,1965235;1985301,1985802;2031864,2032640;2066791,2068485;2099331,2100579;2116848,2119009;2144724,2145184;2192001,2192812;2252449,2253052;2262307,2263154;2264001,2264667;2266226,2266824;2306785,2307404;2312247,2313018;2336987,2337515;2351296,2352518;2385009,2386413;2432759,2433469;2450237,2450885;2456666,2457207;2527072,2527571;2554710,2555533;2556001,2564000;2568001,2568708;2584066,2586457;2606444,2607006;2669646,2671187;2676251,2678534;2697001,2697280;2725392,2726102;2754621,2755149;2816569,2820000;2852324,2852941;2872682,2874445;2924001,2932000;2932291,2932867;2943424,2943787;2946527,2949077;2955790,2956611;2981253,2981843;2985116,2985902;3002170,3006223;3009404,3009514;3018073,3018872;3020748,3021310;3047132,3047767;3107661,3109211;3121053,3121691;3204001,3204674;3221121,3221687;3233718,3234380;3239207,3240000;3254208,3261587;3280576,3281101;3288505,3289240;3300850,3301507;3313033,3313776;3355807,3356764;3365404,3366110;3408904,3409719;3435929,3436469;3456001,3457506;3468670,3469417;3471367,3472000;3547295,3548000;3603085,3604389;3619841,3620191;3621440,3622268;3674188,3682800;3686745,3687240;3688643,3689101;3705561,3706610;3764057,3764706;3767244,3767791;3793215,3793757;3812815,3813643;3831726,3832474;3861283,3861942;3894694,3895388;3965315,3965981;4004296,4004948;4013213,4013797;4021011,4021746;4024997,4025796;4026787,4027469;4034831,4035457;4036614,4038679;4062667,4063254;4116444,4118042;4227745,4228411;4234680,4235245];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1147P %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes: 

% Kahana seizure onset zone: MTL, LTL

% Not enough usable LTL channels. IEDs too widespread. 

% Dominated by line noise. Cannot tell which channels are broken without prior filtering. 
% Must be re-referenced prior to line detection.
% Individual session lines show up in combined, so using re-ref combined for line detection.
% Have to throw out grids to preserve 80-150 Hz activity.

% Could do grid specific re-ref.
% LGR is not saveable. LSP and LPT can be re-referenced with one another. But these are parietal.
% So, maybe not worth it to save LSP and LPT.

% Good number of trials.
% Interictal spikes, deflections, buzz. Will require intensive cleaning.
% 'LAST1', 'LAST2', 'LAST3', 'LPST1' have a fair amount of IEDs
% Lots of buzz and ambiguous IEDs remain, though was somewhat aggressive in cleaning out little blips. Could add them back in.
% Adding a lot more buzz using jumps.

% Channel Info:
info.R1147P.badchan.broken = {'LGR64', 'LGR1' ... % big fluctuations
    'LGR*', 'LSP*', 'LPT*', ... % bad line spectra
    'LPST1'}; % breaks in Session 2

info.R1147P.badchan.epileptic = {'LDH2', 'LDA2', 'LMST2', 'LDH3', 'LDA3', ... % Kahana epileptic
    'LPST6', ... % bad spikes. Confirmed.
    'LMST3', 'LMST4', ... % IEDs and ambiguous slinkies
    'LAST*', ... % IEDs, segment 99
    'LPST3', 'LPST4', 'LPST5', 'LTP1', 'LTP2', 'LTP3', 'LMST1' ... % IEDs, segment 109
    }; 

% Line Spectra Info:
% z-thresh 0.5 + 1 manual
info.R1147P.FR1.bsfilt.peak      = [60  83.2 100 120 140 166.4 180 200 221.4 240 260 280 300 ...
    160];
info.R1147P.FR1.bsfilt.halfbandw = [0.5 0.5  0.5 0.5 0.5 0.5   0.5 0.5 3.6   0.5 0.7 0.5 0.5 ...
    0.5];

% Bad Segment Info: 
info.R1147P.FR1.session(1).badsegment = [392626,393232;401231,401328;414750,414860;416606,416945;434662,436365;441734,442683;453489,454034;458174,459001;470851,471844;479335,481534;481984,482759;483496,484808;485053,486332;488001,489397;493638,493695;498827,500000;511698,511844;520783,525223;528940,529054;539303,542900;543230,544000;548001,549022;552892,553695;554029,554868;562764,563505;566448,567110;569456,573223;577400,578239;578970,579582;582488,584000;592860,593848;595444,596000;605110,605606;624537,625558;634049,634771;644001,644828;649771,651896;655335,656000;660432,661268;667037,671751;674807,675783;676920,677929;680001,682945;692755,693461;707214,708437;721251,722143;742117,742848;765904,766844;768001,770634;776334,778685;783266,785554;794496,795247;796997,797623;804775,804897;810670,811203;823500,824349;829400,829905;846146,847078;853767,854187;858948,860175;876211,877885;892336,893488;895024,897377;903595,903785;904001,905163;907295,907505;919609,920000;929738,930582;933581,933715;943299,944000;949589,950187;955178,956000;974123,975070;981146,981868;984928,992000;994242,999082;1005057,1005667;1013694,1014022;1020658,1021127;1042254,1042586;1058101,1058796;1065166,1065304;1079464,1080361;1096263,1098868;1108928,1109691;1112001,1115590;1116666,1116881;1126710,1127336;1162904,1163054;1177364,1178006;1184094,1185417;1192150,1192974;1210517,1212945;1214343,1219683;1264368,1264998;1320130,1321086;1331730,1332316;1335597,1336421;1336759,1337490;1340912,1344000;1348521,1349264;1366948,1367570;1372936,1373175;1384436,1385066;1410770,1411384;1433138,1433284;1437900,1441215;1468186,1468566;1473247,1473727;1480969,1483009;1489130,1489953;1496823,1497369;1514210,1514441;1517960,1518695;1543585,1545574;1546533,1549881;1550569,1552000;1571766,1572788;1580485,1581264;1619754,1620000;1621372,1622171;1624207,1624836;1642952,1643529;1650597,1654231;1658339,1658751;1674533,1674675;1695492,1696000;1701992,1702151;1758178,1759703;1761964,1762538;1768473,1769324;1776001,1778433;1778775,1780000;1795133,1795670;1813698,1814376;1823351,1823775;1841307,1841993;1847798,1848244;1868001,1870860;1884791,1888000;1936521,1937514;1966879,1967630;1984049,1987017;1988001,1991755;1996094,1996768;2006561,2007158;2009464,2010155;2085126,2085546;2086275,2087344;2088001,2090163;2097372,2097490;2098714,2101832;2120686,2121679;2122436,2122638;2141859,2142747;2168823,2169236;2169682,2170163;2204852,2208000;2222750,2222989;2267214,2267300;2268001,2268566;2306351,2311489;2314448,2314977;2400154,2400772;2404158,2404925;2410500,2411433;2420001,2420925;2424001,2424812;2429489,2429929;2433751,2434348;2439020,2440000;2462138,2462719;2525589,2527610;2528956,2530905;2531077,2531271;2545831,2546538;2556876,2557449;2583464,2584000;2611573,2613852;2621799,2622687;2629190,2629695;2650319,2650755;2661988,2662566;2681783,2682610;2686379,2689421;2716001,2719670;2721670,2723670;2738976,2740615;2753420,2753973;2763730,2765187;2774097,2774501;2784255,2784941;2792533,2793687;2804299,2804841;2817892,2818473;2831274,2832000;2859133,2859699;2924247,2926872;2953489,2954308];
info.R1147P.FR1.session(2).badsegment = [330001,331747;334835,335130;335762,336599;340831,342227;343601,345175;353073,353615;357972,358804;369122,370296;376182,376816;391008,394304;456844,457348;462525,463324;494448,494755;495065,497610;523718,524000;526105,528000;551589,552752;552807,553361;564408,564635;579315,580554;592448,596000;608001,609961;620001,620272;629525,629901;631242,631594;645444,645921;648001,649941;704856,706264;744001,745397;754101,755380;787448,789453;795210,795981;805678,807320;810198,812000;830150,832000;838408,842401;871170,872000;894678,897147;946908,948986;950549,952000;952582,954066;958920,961397;1024130,1024413;1052573,1054800;1057553,1058368;1060223,1062570;1149347,1150368;1164324,1168953;1181420,1182195;1190996,1191163;1198105,1198469];
info.R1147P.FR1.session(3).badsegment = [151117,152000;155722,156000;172614,172832;194375,194743;228916,231791;250553,250715;274738,276000;282811,283050;374835,375163;376001,377739;378492,378715;396795,397183;430533,430820;435532,435679;436001,436429;438359,438598;448263,449510;473944,474179;482779,483118;495141,495344;495561,495787;496178,496752;496819,498550;528134,528526;533908,534195;543653,544522;559770,561703;564787,566126;589682,590054;598202,598598;630017,630763;639573,640925;669634,670973;768658,769788;789388,791025;800001,806122;808694,810300;881932,883812;884146,886852;892848,894767;902202,915840;918388,919634;969779,971352;1017823,1019396;1084299,1084449;1085767,1086663;1089956,1091610;1110392,1112000;1231915,1233324;1238694,1239062;1296815,1298602;1300880,1302590;1332001,1334667;1339778,1340107;1391206,1392312;1461936,1464365;1529541,1531404;1552025,1552933;1554654,1555501;1636122,1638457;1650581,1651118;1661710,1662397];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1149N %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% Kahana seizure onset zone: MTL and occipital
% My seizure onset zone: MTL, occipital, LTL, MPFC

% Widespread but focal IEDs; also smaller, more isolated IEDs
% Buzz episodes

% Good patient; focal IEDs; some ambiguity in how often IED channels are discharging; removed larger, more widespread episodes

% Buzzy channels; keeping them in because of low channel number

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
    'TT*', ... % oscillation with spikes
    'AST3', 'AST4', 'G1', 'G10', 'G11', 'G12', 'G18', 'G19', 'G2', 'G20', 'G3', 'G9', 'MST3', 'MST4', ... % IED, segment 157
    'PST4', ... % mini IED, tracks other channels, segment 160
    'G16', ... % mini IED, isolated, segment 173
    'G4', 'G5', 'OF3', 'OF4', ... % IED, segment 236
    'G8', 'PST2', 'PST4', ... % IED, segment 273
    'G13', 'G14', 'G15', 'G6', 'G7', 'OF1', 'OF2', 'PST3' ... % IED-ish thing, segment 506
    };

% Line Spectra Info:
% Session 1/1 z-thresh 0.5 + manual (small)

% with a bunch of buzzy channels removed, see above for list
% info.R1149N.FR1.bsfilt.peak      = [60  120 180 211.6 220.1000 226.8000 240 241.9000 257.1000 272.2000 280 287.3000 300 ...
%     136 196.5];
% info.R1149N.FR1.bsfilt.halfbandw = [0.6 0.5 1   0.5   0.5000 0.5000 1.3000 0.5000 0.5000 0.5000 0.5000 0.5000 1.4000 ...
%     0.5 0.5];

% with only TT* removed
info.R1149N.FR1.bsfilt.peak      = [60  120 180 196.5 211.7 219.9 220.2 226.8 240 241.9 257.1 272.1 279.9 287.3 300 ...
    105.8 120.9 136];
info.R1149N.FR1.bsfilt.halfbandw = [0.5 0.5 0.7 0.5   0.5   0.5   0.5   0.5   0.9 0.5   0.5   0.5   0.5   0.5   0.9 ...
    0.5   0.5   0.5];

% Bad Segment Info:
% info.R1149N.FR1.session(1).badsegment = [626716,628000;637077,638433;663872,665116;668739,670481;688106,688498;696001,697223;854924,855380;858641,860000;861299,861848;899831,902896;941783,942626;958198,958663;966315,966860;1011549,1011808;1012690,1013276;1055847,1057467;1062424,1063469;1078392,1079900;1091379,1092000;1113110,1114973;1123113,1123832;1146182,1148776;1148856,1149433;1151726,1153687;1177662,1178771;1185799,1186501;1200138,1200893;1225057,1226062;1278706,1278965;1278984,1279489;1414081,1414759;1426186,1426985;1543782,1544095;1554158,1555376;1578512,1584373;1622210,1623324;1665872,1666562;1667520,1669143;1673638,1676724;1678476,1680441;1683097,1683485;1692759,1694199;1714654,1715134;1719729,1720392;1752545,1755779;1765972,1767211;1771516,1773115;1806138,1806751;1828344,1830159;1850093,1851892;1857460,1858090;1888424,1888986;1948118,1954360;1959415,1984000;2006940,2007767;2021198,2024000;2042214,2045187;2099872,2101019;2101571,2102216;2126271,2127243;2136461,2141151;2154206,2155054;2237364,2242969;2279222,2279594;2295726,2296413;2298017,2298852;2308001,2308466;2335948,2336341;2348219,2349530;2355218,2355900;2378589,2387118;2403807,2404252;2495815,2499187;2549787,2551029;2555407,2556776;2567194,2568000;2569827,2570489;2586130,2586594;2677013,2680000;2688029,2691703;2696332,2696965;2705638,2706477;2761384,2764000;2772203,2773570;2819835,2820558;2836610,2837232;2910448,2912000;2943081,2944000;2951460,2952000;2953730,2954683;2984529,2985272;3005372,3006082;3017231,3018763;3021287,3023816;3040162,3040853;3059057,3059715;3079750,3080820;3084001,3086989;3090202,3095106;3102198,3103614;3104001,3107517;3114633,3118909;3153351,3153901;3158226,3161300;3241307,3241574;3242702,3244000;3260001,3260941;3262766,3264000;3268001,3269764;3276001,3279711;3283420,3283945;3285190,3289437;3297218,3298034;3318561,3320000;3320497,3322582;3366658,3369179;3378275,3379001;3457162,3458393;3488670,3489381;3505130,3506804;3526581,3528881];

% Unmarked some buzz episodes.
info.R1149N.FR1.session(1).badsegment = [626716,628000;637077,638433;663872,665116;668739,670481;688106,688498;696001,697223;854924,855380;858641,860000;861299,861848;899831,902896;941783,942626;958198,958663;966315,966860;1011549,1011808;1012690,1013276;1055847,1057467;1062424,1063469;1078392,1079900;1091379,1092000;1113110,1114973;1123113,1123832;1146182,1148776;1151726,1153687;1177662,1178771;1185747,1186417;1200138,1200893;1225057,1226062;1278706,1278965;1278984,1279489;1414081,1414759;1426186,1426985;1543782,1544095;1554158,1555376;1578512,1584373;1622210,1623324;1665872,1666562;1667520,1669143;1673638,1676724;1678476,1680441;1683097,1683485;1692759,1694199;1714654,1715134;1719729,1720392;1752545,1755779;1765972,1767211;1771516,1773115;1806138,1806751;1828344,1830159;1850093,1851892;1857460,1858090;1888424,1888986;1948118,1954360;1960001,1970737;1972001,1982024;2006940,2007767;2021198,2024000;2042214,2045187;2099872,2101019;2101571,2102216;2126271,2127243;2136461,2141151;2154206,2155054;2237364,2242969;2279222,2279594;2295726,2296413;2298017,2298852;2308001,2308466;2335948,2336341;2348219,2349530;2378589,2387118;2403807,2404252;2495815,2499187;2549787,2551029;2555407,2556776;2567194,2568000;2586130,2586594;2677013,2680000;2688029,2691703;2696332,2696965;2705638,2706477;2761384,2764000;2772203,2773570;2819835,2820558;2836610,2837232;2910448,2912000;2943081,2944000;2951460,2952000;2953730,2954683;2984751,2985288;3005372,3006082;3017231,3018763;3021287,3023816;3040162,3040853;3059057,3059715;3079750,3080820;3084001,3086989;3090202,3095106;3102198,3103614;3104001,3107517;3114633,3118909;3153351,3153901;3158226,3161300;3241307,3241574;3242702,3244000;3260001,3260941;3262766,3264000;3268001,3269764;3276001,3279711;3283420,3283945;3285190,3289437;3297218,3298034;3318561,3320000;3320497,3322582;3366658,3369179;3378275,3379001;3457162,3458393;3488670,3489381;3505130,3506804;3526581,3528881];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1151E %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1151E' - 3    - 7T   - 9F    - 208/756   - 0.2751   - 7T   - 9F    -  202/742 -   0.2722               - :)  - Done.
% 'R1151E' - 1/3  - 7T   - 9F    - 77/300    - 0.2567   - 7T   - 9F    -  76/294  -   0.2585                 
% 'R1151E' - 2/3  - 7T   - 9F    - 83/300    - 0.2767   - 7T   - 9F    -  81/296  -   0.2736                 
% 'R1151E' - 3/3  - 7T   - 9F    - 48/156    - 0.3077   - 7T   - 9F    -  45/152  -   0.2961                 

% Pretty bad noise specific to surface channels. Re-ref before line spectra helps find sharp spectra.
% Using combined re-ref for detecting peaks
% Remaining channels are kinda coherent and slinky, but nothing major.
% No spikes, just occasional buzz. Relatively clean.
% Session 3 goes bad from time 2100 onward, also between 1690 and 1696.
% Great trial number and accuracy, but poor coverage.
% Exceptionally clean. Barely any IDEs, and no buzz.
% Lots of tiny spikes. Removing a few with jumps. Probably overkill. 
% TRY THIS SUBJECT FOR PHASE ENCODING. Very curious if channel pairs will be present.

% Channel Info:
info.R1151E.badchan.broken = {'RPHD8', 'LOFMID1' ... sinusoidal noise and fluctuations, session 1
    };
info.R1151E.badchan.epileptic = {'LAMYD1', 'LAMYD2', 'LAMYD3', 'LAHD1', 'LAHD2', 'LAHD3', 'LMHD1', 'LMHD2', 'LMHD3', ... % Kahana
    }; 

% Line Spectra Info:
% Lots of line spectra, but baseline is pretty ok. 
info.R1151E.FR1.bsfilt.peak      = [60  180 210.2 215 220.1 300 ...
    100 120 123.7 139.9 239.9 247.3 260];
info.R1151E.FR1.bsfilt.halfbandw = [0.5 0.5 0.5   0.5 0.5   0.5 ...
    0.5 0.5 0.5   0.5   0.5   0.5   0.5];

% Bad Segment Info:
info.R1151E.FR1.session(1).badsegment = [1158351,1158997;1187480,1188000;2215746,2216458;2442105,2445397;2804473,2804651;2821460,2822175;2936114,2936732;2984501,2984957;3211246,3211896;3236166,3236542;3326883,3326993];
info.R1151E.FR1.session(2).badsegment = [443827,444183;580086,580449;592670,592937;1261920,1262280;1350787,1350961;1535335,1535554;1623488,1624000;1781710,1783521;1829077,1829236;2129376,2129695;2540642,2540965;2860497,2862203];
info.R1151E.FR1.session(3).badsegment = [706948,707650;1130569,1131340;1169130,1169619;1211544,1212191;1282444,1282993;1284473,1285469;1379367,1380000;1477158,1477562;1480279,1480764;1507073,1520000];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1154D %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 52/245 - 0.21224
% 94/251 - 0.3745
% 85/263 - 0.32319

% 231/759 - 0.3043

% No Kahana electrode info available.
% Me: MTL, parietal, occipital

% Lots of line spectra, though remaining baseline is flat.
% Needs LP.

% Some buzz that can be removed by re-ref.

% Big IEDs in LOTD depths.

% Very clean subject. Discrete focal IEDs, almost no bleedthrough to remaining surface. Fits all assumptions. 

% Discrete large events, decent number of slinky channels, decent number of low-amplitude fluctuating channels.
% Using combined session re-ref for line detection, plus manual adding of other peaks from individual sessions
% Nothing that makes me distrust this subject.
% Session 2 is corrupt after 2738 seconds.
% Session 2 still has buzzy episodes after re-ref and LP.
% Very slinky channels in Session 2, might be worse than Session 1.
% First 242 seconds of Session 3 are corrupted.
% Session 3 is very buzzy too.
% Buzzy. No IEDs. Jumps help a lot.
% LTCG* saved by re-referencing separately. From 10/19 to 37/19. {{'all', '-LTCG*'}, {'LTCG*'}};

% Channel Info:
info.R1154D.badchan.broken = {'LOTD*', 'LTCG23', ... % heavy sinusoidal noise
    'LTCG*', ... % bad line spectra
    'LOFG14' ... % big fluctuations in Session 2
    }; 
info.R1154D.badchan.epileptic = {'LSTG1', ... % intermittent buzz LSTG2
    'LSTG7' ... % oscillation + spikes
    };

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
info.R1154D.FR1.session(1).badsegment = [240045,241957;307077,308990;342827,344000;378186,379054;441867,442675;480904,482276;492223,495142;516977,518840;526770,527759;529214,530485;609722,611421;718863,721260;742432,745320;846960,847852;865400,867118;871875,873082;884569,885365;917364,918804;942097,943844;1040090,1042014;1075851,1077957;1136332,1138114;1148932,1149453;1197456,1198284;1240477,1242832;1268001,1269864;1273489,1275090;1347440,1347836;1526125,1528877;1539835,1541078;1561214,1562751;1566811,1568740;1641420,1642405;1696598,1697219;1718863,1720377;1762827,1766042;1840146,1840663;1907145,1908000;1932948,1935029;1974545,1975828;1986347,1987791;2045956,2046518;2114013,2114546;2129384,2131856;2248211,2248845;2272190,2274421;2308376,2309687;2332001,2334453;2382492,2384397;2388815,2390026;2439573,2441070;2457106,2457989;2469227,2470896;2473654,2474453;2483440,2485433;2486545,2487606;2492973,2493941;2548670,2550159;2572106,2573756;2599121,2601296;2639109,2642489;2648291,2650106;2684013,2686513];
info.R1154D.FR1.session(2).badsegment = [180295,182844;226718,229457;286371,288300;334726,338215;348469,350812;365730,366642;372497,374739;385069,388000;432880,436000;510117,511158;540860,545119;550057,552000;586819,589268;634170,634909;644001,646767;649472,651832;675319,677361;691238,694022;742879,744421;747831,750735;751045,753856;841412,842856;884920,886235;927520,928000;1001299,1004000;1029122,1031138;1035520,1036990;1058605,1059509;1060981,1061881;1065102,1067957;1085347,1088000;1158678,1162401;1165726,1169006;1176368,1180000;1183407,1184236;1212114,1212820;1260001,1263481;1266585,1268506;1283008,1284720;1327162,1327590;1410343,1411231;1440150,1442405;1462601,1463654;1566279,1570691;1587162,1588611;1663750,1665276;1684819,1687485;1744001,1746711;1767528,1768000;1768094,1773796;1779097,1781433;1789372,1789868;1864271,1865889;1872356,1873542;1881622,1882977;1925057,1925606;1958754,1960000;1969730,1971864;1981440,1982848;2053807,2055029;2055069,2055896;2069992,2070626;2086371,2087751;2090823,2093030;2255424,2257090;2263250,2265352;2267041,2267590;2268340,2269598;2272948,2274389;2276779,2278909;2317388,2317981;2384340,2386776;2386799,2387767;2388360,2390300;2392557,2396000;2397436,2399308;2399678,2401373;2469489,2472982;2475351,2476000;2476711,2477945;2491190,2492788];
info.R1154D.FR1.session(3).badsegment = [496690,497481;530658,535759;536311,540000;540489,543759;548001,550949;554662,555751;564001,566433;594069,594993;634105,636000;637283,638509;641908,644000;647113,648615;656924,659025;660190,664792;668001,669377;724283,725425;739395,741631;742512,744000;757843,758163;768803,769848;790561,791477;850537,850739;850762,852961;857702,858840;863016,866304;868380,869635;927190,930630;936582,938187;963432,964812;983706,985635;1026912,1028599;1039299,1040760;1041803,1043848;1073900,1076000;1098609,1099606;1197730,1200000;1254210,1255114;1320565,1320643;1342823,1348000;1359508,1362655;1389545,1390562;1451831,1452994;1530404,1533812;1546299,1548000;1552001,1554078;1556001,1557957;1578654,1579888;1643182,1644635;1700001,1700796;1700823,1701453;1761827,1762445;1768001,1768965;1773718,1775775;1826222,1828000;1856598,1857780;1881811,1885598;1947226,1950884;1956001,1960000;1970198,1972000;2040001,2040712;2053440,2055090;2082936,2084804;2141521,2143078;2161102,2162481;2169501,2171715;2178142,2178812;2196001,2197610;2263024,2266340;2337726,2338723;2376303,2378344;2410408,2411489;2418452,2419662;2419702,2421086;2488848,2489917;2594811,2594896;2604775,2606393;2613529,2613881;2644082,2644550;2649892,2650937;2674025,2675695;2787081,2788000;2802295,2803751;2893468,2894397;2974492,2975727;2976247,2978965;2988001,2988998;3034464,3035558;3097037,3098207];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1162N %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% Quite a few foci. Trying to get them all.
% Some ambiguity, but otherwise seems ok.

% No Kahana electrode info available.
% Me: LTL, MTL, occipital, parietal

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
info.R1162N.badchan.epileptic = { ...
    'ATT1', 'ATT2', ... % IED, segment 432
    'PLT4', 'PLT5', ... % IED, segment 436
    'MLT4', ... % IED, segment 153
    'PLT1', ... % IED, 167
    'MLT2', 'MLT3', ... % IED, 176
    'PLT3', ... % IED, 291
    'ILT4', ... % IED, 343
    'ILT1', 'ILT2', 'ILT3' ... % IED, 649
%     'AST1', 'AST2', 'AST3', 'ATT3', 'ATT4', 'ATT5', 'ATT6', 'ATT7', 'ATT8', ... % synchronous spikes on bump
%     'ATT1' ... % bleed through from depths
    };

% Line Spectra Info:
info.R1162N.FR1.bsfilt.peak      = [60  120 180 239.5 300 ... % Session 1/1 z-thresh 1
    220]; % manual, tiny tiny peak
info.R1162N.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5   0.6 ...
    0.5]; % manual, tiny tiny peak

% Bad Segment Info:
info.R1162N.FR1.session(1).badsegment = [561726,561768;576630,577385;608719,609103;624259,624804;665485,666054;671935,672472;676001,676441;681364,682010;685743,686340;697900,698776;701698,702368;767883,768679;769509,772196;780287,782651;785948,786578;801243,801659;870001,870614;871847,872808;876001,877610;882476,883171;929392,930578;956376,958542;966835,967912;968860,973481;975073,975932;1045747,1047550;1047569,1048000;1056606,1057719;1059194,1060276;1062105,1064000;1133944,1135163;1137811,1138110;1139081,1140000;1152001,1153074;1163573,1164000;1165114,1165615;1168461,1169223;1171238,1172000;1189428,1190675;1192985,1194034;1198206,1198735;1238315,1239029;1240799,1241764;1283448,1283634;1283665,1284510;1285791,1286376;1322279,1323066;1368130,1368764;1422621,1422711;1446670,1447203;1448856,1450094;1451295,1452000;1469110,1471872;1482460,1482921;1484795,1485631;1521497,1521748;1522694,1524304;1541863,1543868;1557565,1558066;1559399,1560000;1563544,1564800;1623117,1624000;1625210,1627259;1640646,1643316;1648207,1648587;1648598,1651271;1661222,1661691;1668267,1668998;1671311,1672599;1675278,1676000;1677069,1677776;1722476,1723231;1724920,1726030;1738307,1738941;1741283,1741744;1752549,1753328;1766033,1766663;1768178,1769449;1771391,1771731;1789343,1790780;1803278,1803916;1822908,1823541;1832799,1834417;1835460,1838961;1840001,1842340;1847544,1848707;1856001,1856591;1910355,1911005;1912001,1912631;1915403,1915937;1945920,1947062;1948315,1949272;1950013,1951025;1953001,1956333;1958609,1959223;1960928,1961530;1962738,1964000;2017759,2018675;2037331,2038276;2040029,2040933;2064324,2065252;2089787,2090304;2098581,2099836;2105823,2106219;2106226,2106707;2108844,2109481;2113126,2113784;2127077,2127550;2129295,2131429;2142617,2143820;2151238,2151876;2153323,2154018;2233670,2235860;2243117,2243880;2329049,2329675;2354948,2355606;2392001,2392433;2397001,2397760;2398416,2399042;2402319,2402836;2417775,2418280;2419129,2419687;2419706,2420365;2423544,2424000;2429057,2430550;2432239,2433953;2446666,2447263;2486533,2487215;2499073,2499852;2511367,2512000;2544066,2545014;2582480,2583283;2584005,2584695;2584763,2586054;2586295,2587110;2587617,2588000;2588884,2589522;2593376,2594227;2617690,2618163;2618968,2619755;2620904,2621381;2621597,2622505;2643629,2644437;2672388,2672619;2682170,2683046;2683879,2684401;2690291,2691529;2695291,2695715;2712541,2713086;2718158,2719707;2755012,2755759;2812864,2813348;2828840,2829340;2836001,2836506;2875202,2876111;2879278,2880000;2880654,2881139;2882641,2883348;2884376,2884957;2904557,2905010];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1166D %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 27/284 - 0.09507
% 47/277 - 0.16968
% 46/283 - 0.16254

% 120/844 - 0.1422

% Seizure onset zone "unreported".
% My seizure onset zone: parietal

% Ambiguous, but focal IEDs. Channels LFPG6/7 seem to get slinky, then progress to slightly larger fluctuations. Marked ones with swoop.
% Mostly buzz episodes.

% A good, but mildly ambiguous subject.

% LFPG seem kinda wonky. Needs re-referencing and LP filter before cleaning. Lots of buzz still.
% Session 2: maybe some slight buzz and "ropiness" on LFPG temporal channels (24, 30-32).
% A few line spectra between 80 and 150Hz, but much smaller with re-ref
% Line detection on re-ref. 
% Buzzy episodes need to be cleaned out.
% No major events or slink, but buzz is worrying. 
% Lots of trials, low accuracy, ok coverage.
% Buzzy. No avoiding the buzz.
% LSFPG* can be re-refed separately. 5/19 to 5/35. {{'all', '-LSFPG*'}, {'LSFPG*'}};
% Adding a couple of things with jumps, but is still very buzzy. Cannot be helped.

% Channel Info:
info.R1166D.badchan.broken = {'LFPG14', 'LFPG15', 'LFPG16', ... % big deflections
    'LSFPG*', ... % bad line spectra
    'LFPG10' ... % big fluctuations in Session 3
    };
info.R1166D.badchan.epileptic = { ...
    'LFPG5', 'LFPG6', 'LFPG7', 'LFPG8' ... % wonky fluctuations together with one another
    }; 

% Line Spectra Info:
info.R1166D.FR1.bsfilt.peak      = [60  120 180 200 217.8 218.2 218.8 220.1 223.7 240 300 ...
    100.1 140 160 260 280];
info.R1166D.FR1.bsfilt.halfbandw = [0.5 0.5 0.5 0.5 0.5   0.5   0.5   0.5   1.6   0.5 0.5 ...
    0.5   0.5 0.5 0.5 0.5];

% Bad Segment Info:
info.R1166D.FR1.session(1).badsegment = [20271,22642;467702,472510;564295,566050;568948,575779;575831,576921;576997,588986;607544,607626;610960,614018;620856,622376;717557,722586;1064001,1066534;1160453,1163199;1171198,1175638;1176287,1177518;1284001,1285558;1309480,1311090;1313227,1315408;1331815,1333816;1335637,1335699;1336001,1338006;1390279,1390626;1405803,1406860;1407081,1408000;1410073,1416578;1429799,1431533;1549158,1552369;1557089,1558671;1771383,1773953;1775274,1776000;1844001,1848000;1877807,1878594;1878762,1883110;1964831,1968000;1972001,1976000;1976448,1978312;2109509,2112000;2112884,2116000;2116799,2120000;2120892,2123989;2126666,2130179;2138311,2140000;2153134,2156000;2156372,2158255;2172001,2176000;2185815,2186880;2190702,2191429;2196416,2197578;2294383,2298634;2310613,2312000;2452001,2452764;2485932,2487384;2500860,2504329;2505428,2505949;2672328,2675783;2710670,2711699;2812844,2814324;2917162,2920000;3037061,3039163;3056606,3058570;3089924,3091884;3093319,3094098;3095794,3096000;3125690,3128000;3132082,3134876;3235432,3238219];
info.R1166D.FR1.session(2).badsegment = [288505,289856;473771,476000;479492,480627;511186,512486;552888,556736;740001,742570;995629,996635;1220594,1223840;1224791,1226711;1300682,1302066;1304618,1306183;1496368,1497260;1506549,1508000;1654371,1656619;2268211,2269490;2364372,2366304;2368964,2370860;2465271,2467348;2470170,2472965;2485880,2487541;2576706,2579130;2692783,2694401;2710847,2713111;2793791,2800925;2801718,2803465;2815399,2816000;2828001,2828312;2828380,2832000;2832215,2839433;2840001,2842118;2846819,2847368];
info.R1166D.FR1.session(3).badsegment = [315069,315118;498605,500204;634779,636000;636186,636224;732162,733558;852259,854981;874895,880000;880537,883687;908831,908889;910130,912873;1040787,1043094;1112549,1114647;1233775,1237405;1244001,1248000;1253924,1254042;1291379,1293699;1304690,1307308;1327012,1339158;1430125,1438384;1440001,1441659;1442662,1445570;1603335,1606255;1607524,1612000;1716420,1718554;1760307,1764873;1765231,1766921;1926621,1927570;1987307,1989409;2037932,2040000;2077210,2077288;2280642,2284000;2405686,2408000;2533468,2547550;2549464,2551179;2680324,2681816;2784134,2785344;2807355,2818457;2894686,2899029;2948106,2948603;2990299,2992784];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1167M %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1167M' - 2    - 42T  - 21F   - 166/372   - 0.4462   - 32T  - 19F   - 133/285   - 0.4508 - :)  - Done. 
% 'R1167M' - 1/2    - 42T  - 21F   - 80/192   - 0.4167  - 32T  - 19F   - 54/127    - 0.4252    
% 'R1167M' - 2/2    - 42T  - 21F   - 86/180   - 0.4778  - 32T  - 19F   - 79/158    - 0.5 

% 74/149 - 0.49664
% 53/127 - 0.41732
% 127/276 - 0.4601

% Kahana: LTL, parietal, motor
% Me: LTL, occipital, parietal, motor

% Very ambiguous IEDs in Session 1.

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
    'LAI1', 'LAI2', ... % high frequency noise on top
    'LPT4', 'LPT5', 'LPT6', 'LPT9', ... % frequent little spikes. Removed after jumps. Probably could keep, but would need to remove more trials.
    'LAI4', 'LAT1', 'LAT9', 'LAT10', 'LPT1', 'LPT2', 'LPT3', 'LPT7', 'LPT8', ... % IED, 2.99
    'LPT22', 'LPT23', 'LPT24', ... % IED, 2.172
    'LPT10', 'LPT11', ... % IED, 2.222
    'LPT14', 'LPT15', 'LPT16', 'LPT17', ... % IED, 1.51
    'LPT13', 'LPT19', 'LPT20', 'LPT21', ... % IED, 1.65
    'LAT2', 'LAT3', 'LAT3' ... % IED, 1.102
    }; 

%     'LPT10', 'LPT11', 'LPT12', 'LPT14', 'LPT15', 'LPT16', 'LPT17', ... % IED, 1.51
%     'LAI3', 'LAI4', ... % IED, 1.53
%     'LPT13', 'LPT19', 'LPT2', 'LPT20', 'LPT21', 'LPT22', 'LPT23', 'LPT3', ... % IED, 1.65


% Line Spectra Info:
% z-thresh 0.45 + manual on combined re-ref. 
info.R1167M.FR1.bsfilt.peak      = [60  100.2 120 180 199.9 220.5 240 259.8 280 300 ...
    95.3 96.9 139.6 140.7 160 181.3];
info.R1167M.FR1.bsfilt.halfbandw = [0.5 0.5   0.5 0.5 0.5   2.9   0.5 0.8   0.5 0.5 ...
    0.5  0.5  0.5   0.5   0.5 0.5];

% Bad Segment Info:
info.R1167M.FR1.session(1).badsegment = [3574,5023;5468,6466;7684,8419;20092,21001;27678,28668;37140,37356;41003,41646;62699,63278;65901,66791;89033,89431;91999,92000;117221,117660;136656,137620;139916,140708;142906,143850;158062,159796;163129,163485;176904,177536;178280,180360;182616,183404;200711,201461;219404,220959;248489,248534;254158,254578;259244,259901;280757,281423;281884,282380;282387,283598;295774,295828;298500,299094;319716,320842;350932,351009;358871,358909;361291,361631;388969,389514;389527,390109;390130,391017;392979,394052;394845,396647;397072,400425;401626,404000;407347,408154;409368,414888;427270,427912;428844,430280;430331,430933;448796,449321;451728,452340;472827,472889;477097,477888;484158,487566;497791,498131;500888,501232;522440,523038;523476,525796;529452,529490;530239,530838;544917,546668;549464,551091;551159,552783;554487,555525;556390,557297;557584,558549;562140,562842;563936,563973;568202,568926;572646,574098;575718,576623;583653,584163;585261,586133;586674,587743;587840,588728;591693,592906;600541,600942;602554,603178;605148,605853;611812,612292;619218,619861;620621,621442;621464,622324;626484,628000;629243,629816;633465,634036;635083,636000;642791,643106;643690,645336;645339,645810;653232,653797;711488,711820;722954,723589;725126,725578;727312,728000;729053,731231;743640,743893;751424,751848;758970,759971;774920,775662;777323,777768;778730,779134;790460,790860;797517,800663;817089,817441;828001,828835;839301,840492;846428,847356;848726,849310;851048,852000;855561,856405;856565,857369;863818,864484;868917,869466;877763,880000;883012,883731;907337,908687;919839,920226;921205,921545;927640,927896;931485,932478;942456,942856;956811,959122;959125,961379;973484,974176;982567,983157;987855,988357;995021,995686;1018851,1019154;1031196,1031888;1060001,1063199;1064666,1064965;1066766,1067399;1082519,1083262;1084001,1084665;1122833,1123525;1137674,1138074;1140299,1143364;1148001,1148475;1149057,1150058;1150174,1150848;1152001,1153308;1169976,1170328;1220513,1220949;1223363,1224324;1244224,1245262;1258109,1258727;1258919,1259622;1265876,1265937;1275375,1276000;1286025,1286638;1296151,1296902;1297925,1298592;1344863,1346254;1346844,1347455;1398360,1398953;1402517,1404732;1413788,1415528;1422408,1423844;1430742,1431880;1439836,1440518;1441744,1442148;1495851,1495908;1496329,1498259;1503432,1504000;1573672,1574388;1588989,1591699;1594698,1595034;1599549,1600000;1604001,1604612;1607180,1607904;1637081,1638219;1651157,1651654;1663041,1663916;1704674,1705143;1706114,1706731;1707339,1708000;1716406,1716609;1718613,1718659;1720831,1724000;1727371,1727421;1730910,1732000;1739246,1739271;1742024,1742603;1750967,1753644;1754001,1754562;1782605,1782659;1790130,1790179;1826432,1828000;1833041,1833878;1835602,1836443;1866488,1867320;1870617,1871545;1873549,1874296;1888001,1888449;1914645,1916000;1921750,1922738;1936519,1937198;1938019,1938848;1939298,1939923;1940001,1941873;1948190,1948252;1952208,1952773;1957008,1957982;1975835,1976458;1977872,1978622;2027457,2027804;2029132,2029418;2037909,2038130;2041406,2041843;2052001,2052515;2055811,2056541;2068847,2069706;2077003,2077808];
info.R1167M.FR1.session(2).badsegment = [59923,60574;63558,64259;69264,70353;74277,75329;102823,103434;127279,127974;140041,140469;143352,143708;165656,166595;194006,194872;196796,197321;227866,228426;262261,263082;372457,373615;373872,375779;393198,395179;409884,410929;412001,412421;417432,418026;433952,434667;434867,435163;435182,435614;439331,439945;463081,464143;497213,498318;508046,511313;521827,522792;535726,536349;543464,543723;543768,544568;546468,546723;552231,552558;574976,575767;589987,592945;592977,595287;617678,617723;628944,629832;637222,637856;686174,686594;760151,761310;764501,766046;777127,778127;778174,779110;828060,831995;832001,835990;836001,839998;840001,855998;856001,860000;886379,886792;918968,919324;1001275,1003537;1005114,1005610;1014275,1014679;1038021,1038715;1050585,1051017;1097158,1097691;1138879,1140902;1147774,1148000;1164041,1164953;1212364,1214106;1216001,1217700;1318843,1318888;1348001,1349012;1381464,1384353;1399452,1400476;1400541,1401675;1414706,1414747;1418069,1418135;1421859,1421901;1422694,1424957;1447118,1447458;1447476,1447699;1501480,1501510;1606791,1607545;1607836,1608403;1632952,1633012;1654379,1655022;1669581,1670401;1704256,1706160;1729771,1731679;1810319,1812000;1821799,1823014;1832780,1836000;1836288,1838958;1848208,1848875;1859519,1860319];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1175N %%%%%% 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:

% 'R1175N' - 1    - 39T  - 29F   - 68/300  - 0.2267   - 27T  - 26F - 57/262 - 0.21756                       - :) - Done. 

% No Kahana electrode info available.
% Me: everywhere

% What's left seems clean. 

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
% Removing a bunch of discontinuities using jumps. Looks like most of these are in non-trial data.

% Channel Info:
info.R1175N.badchan.broken    = {'RAT8', 'RPST2', 'RPST3', 'RPST4', 'RPT6', 'RSM6', 'RAF4'};
info.R1175N.badchan.epileptic = { ...
    'RAT1', 'RMF3', ... % IEDs isolated to single channels
    'LPST1', 'RAST1', 'RAST2', 'RAST3', 'RAST4', ... % more IEDs
    'RPT1', 'RPT2', 'RPT3', 'RPP3', 'RPP4', 'RAT2', 'RAT3', ... % IED, 353
    'RMF4', 'RMF5', 'RPF1', ... % IED, 364
    'RMP1', 'RMP2', 'RMP3', ... % IED, 407
    'RPST1', ... % IED, 410
    'LAST1', 'LAST2', 'LAST3', 'LPST2', ... % IED, 427
    'RPT4', 'RPT5', ... % IED, 488
    'RAF1', 'RAF2', 'RAF3', 'RAF5', ... % IED, 492
    'RPP5', 'RPP6', ... % IED, 426
    'RMF6', 'RMF8', 'RSM4', 'RSM5', ... % IED, 527
    'RMF2', ... % IED, 531
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', ... % IED, 550
    'LAST4', 'LAT1', 'LAT2', 'LPST3', 'LPST4', ... % IED, 623
    'RAF6', 'RMF7', 'RPF2', 'RPF3', 'RSM3', ... % IED, 731
    'RSM1', 'RSM2', 'RAF7' 'RAF8', ... % IED, 734
    'RMP5', ... % IED, 779
    'LAT3', 'LAT4', 'LAT5', 'LAT6', 'LPT6' ... % IED, 861
    };

% 'RAT2', 'RAT3', 'RAT4', 'RAT5', 'RAT6' ... % synchronous spike on bump

% Line Spectra Info:
info.R1175N.FR1.bsfilt.peak      = [60  120 180 220 240 280 300.2 ... % Session 1/1 z-thresh 0.5
    159.9 186 200 216.9 259.9]; % manual
info.R1175N.FR1.bsfilt.halfbandw = [0.6 0.8 1.6 0.5 3   0.5 4.6 ... % Session 1/1 z-thresh 0.5
    0.5   0.5 0.5 0.5   0.5]; % manual

% Bad Segment Info:
info.R1175N.FR1.session(1).badsegment = [1369227,1369542;1375355,1375416;1380001,1380175;1384134,1384320;1410383,1411227;1417940,1417993;1428582,1429357;1446488,1446550;1446815,1446872;1447516,1447570;1447629,1447679;1448287,1449038;1449102,1450300;1452001,1452316;1452352,1452393;1453569,1453651;1454795,1456000;1464174,1464272;1466121,1466227;1470456,1470505;1470807,1471586;1518117,1518642;1520553,1520877;1532694,1532732;1533311,1534344;1537247,1537929;1548061,1548099;1548823,1548869;1552997,1553344;1554537,1554578;1555782,1555808;1568747,1569155;1569162,1569300;1569726,1569816;1571915,1572000;1573239,1573332;1574029,1574110;1574839,1574905;1578315,1578372;1584146,1584832;1621601,1622397;1624557,1625183;1629150,1629256;1637497,1638078;1652448,1652510;1655561,1656000;1656066,1656155;1656358,1658852;1661485,1661582;1661714,1662376;1678718,1678767;1686005,1686062;1702069,1702731;1703831,1704000;1704414,1705359;1725497,1725812;1725839,1726372;1727085,1727328;1732408,1732462;1733807,1733856;1741529,1741562;1748771,1748816;1750045,1750332;1750887,1750973;1763593,1764000;1766758,1768000;1774210,1774469;1802061,1802191;1802730,1803058;1803480,1803650;1804082,1805744;1807657,1809042;1811012,1812280;1814146,1814187;1818452,1818518;1819420,1819529;1820283,1820385;1820741,1821056;1824235,1826066;1829609,1829965;1835053,1835304;1845738,1846191;1849686,1849776;1857573,1857739;1859903,1860272;1863363,1863461;1865940,1866461;1882069,1882143;1934448,1934804;1936783,1937542;1939452,1940000;1941162,1941768;1943524,1944296;1946424,1947110;1948166,1948752;1951327,1951739;1954460,1955267;1964670,1965421;1973029,1973187;1973589,1973973;1975649,1976502;1978831,1978880;1979315,1979864;1980344,1980712;2017069,2017179;2024122,2024707;2028001,2028994;2041335,2042058;2042343,2042872;2057549,2057647;2057928,2058022;2066891,2066985;2068513,2068800;2071097,2071735;2071784,2072000;2073650,2073727;2074730,2074804;2075794,2075949;2077214,2077280;2077839,2077941;2081126,2081195;2081380,2081502;2089682,2089788;2094686,2094808;2106879,2107836;2122956,2124000;2124920,2126086;2128513,2129046;2164247,2165074;2176416,2176542;2176565,2176764;2182770,2182888;2187786,2187928;2190432,2190550;2196211,2196502;2196936,2197050;2199270,2199352;2199375,2200000;2205622,2205695;2206444,2207094;2212275,2212304;2213130,2213211;2213480,2213578;2214307,2214441;2215936,2216385;2228275,2228699;2228723,2228982;2240078,2240377;2242597,2243691;2244404,2245340;2247621,2248000;2254488,2255118;2267218,2267618;2283315,2283715;2287137,2287247;2294158,2294260;2294343,2294642;2294706,2294848;2297884,2297989;2298202,2298231;2299117,2299316;2312396,2312486;2321972,2322759;2373831,2376000;2406327,2407372;2408565,2409651;2435859,2436000;2437932,2438876;2444315,2444417;2452118,2452208;2482242,2483755;2483819,2484288;2485323,2485985;2490303,2491340;2514093,2514159;2518787,2518836;2528876,2528949;2558553,2559977;2563020,2563102;2567045,2567812;2571153,2572264;2573872,2573941;2590968,2591054;2592001,2592381;2592694,2592800;2595295,2597226;2605255,2606574;2638557,2639134;2650327,2650389;2657432,2657550;2659625,2659687;2662823,2662921;2666210,2666284;2667174,2667243;2672852,2672913;2675125,2675296;2675823,2675937;2676396,2676478;2679790,2679872;2684848,2685014;2690545,2691271;2694432,2694518;2700912,2701985;2708831,2708877;2711682,2712510;2712694,2712756;2712908,2713034;2713533,2713602;2714343,2716000;2721497,2721574;2727399,2727485;2733928,2734006;2736001,2736836;2739669,2740454;2744090,2744167;2744844,2744921;2752223,2752530;2756848,2756893;2759214,2760000;2760368,2760433;2769057,2769127;2769734,2769897;2771492,2771550;2772948,2773046;2781952,2782030;2786512,2786558;2786940,2788000;2788203,2788264;2789001,2789115;2790234,2790324;2790762,2790856;2791492,2791650;2806779,2807558;2810138,2810223;2814412,2815064;2819476,2819695;2850319,2850723;2880533,2880655;2883383,2883453;2884114,2884167;2886533,2886582;2889122,2889207;2904864,2904974;2905396,2905449;2906154,2906247;2906726,2907191;2909037,2909082;2913323,2913449;2920126,2920806;2933747,2934759;2934811,2935562;2948328,2949199;2960061,2960131;2978287,2979154;2980283,2981058;2987178,2987271;2987553,2987884;3005747,3006147;3038541,3038836;3043867,3044308;3047919,3048994;3054541,3055239;3056416,3056897;3059099,3060000;3072424,3072982;3076823,3076869;3076977,3077034;3077960,3078034;3092162,3093141;3093198,3094284;3098920,3099126;3099371,3099425;3103540,3103638;3108352,3108389;3110190,3110292;3113098,3113723;3126041,3126122;3129823,3129945;3131109,3131247;3132315,3133167;3166851,3167267;3180779,3181582;3190920,3191614;3194899,3195840;3203516,3203618;3206944,3207086;3214178,3214215;3224207,3224514;3239940,3240123;3240755,3240873;3244219,3244841;3250381,3252000;3262791,3263495;3266750,3267106;3270662,3271400;3275375,3275735;3283686,3284000;3285275,3285453;3286631,3287263;3311295,3312000;3319319,3319558;3324805,3325631;3376118,3376901;3389847,3390151;3441988,3443062;3444057,3444139;3446355,3446413;3453609,3453655;3454166,3454251;3458613,3458679;3461319,3462788;3468840,3468913;3475686,3475791;3482432,3482937;3484001,3484075;3502811,3503219;3504537,3505002;3556473,3557288;3579109,3579860;3583544,3584264;3598444,3599223;3602125,3603348;3615540,3616000;3636082,3636280;3649098,3649844;3656384,3657054;3676436,3680000;3689690,3689735;3691033,3716000;3743303,3743928;3758553,3759062;3760872,3762203;3763363,3764000;3771319,3771803;3776940,3777292;3781698,3782151;3798440,3799130;3806178,3806808;3820372,3820994;3834775,3835223;3838670,3839376;3846871,3847130;3850311,3851376;3887786,3888320;3921444,3921731;3933787,3934292;3958077,3958384;4036384,4037397;4093335,4094018;4102009,4102562;4118936,4119356;4140981,4141490;4146883,4147912;4172001,4173123;4183428,4184000;4187504,4188000;4191137,4191215;4225077,4226264;4228616,4228818;4231359,4231465;4232791,4233437;4234436,4234751;4245041,4246630;4264299,4265937;4281892,4283275;4303900,4304977;4306621,4307481;4313706,4314207;4329392,4329885;4337222,4337860;4363198,4363622;4367488,4368000;4370254,4370542];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%% R1128E %%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Notes:
% REMOVED BECAUSE OF SWITCH TO INDIVIDUAL REGION LABELS. AFTER CLEANING, ONLY 2T REMAIN.
% 'R1128E' - 1    - 8T   - 10F   - 141/300   - 0.4700   - 4T   - 9F    - 134/276   - 0.48551  - :)  - Done. Core. 26. 147 recall. 

% Mostly depth electrodes. Very frequency epileptic events that are present
% in temporal grids.
% Ambiguous IEDs, not sure if I got them all OR if I was too aggressive. 
% RANTTS5 is mildly buzzy, but keeping in

% Not great for phase encoding.

% Channel Info:
info.R1128E.badchan.broken = {'RTRIGD10', 'RPHCD9', ... % one is all line noise, the other large deviations
    };
info.R1128E.badchan.epileptic = {'RANTTS1', 'RANTTS2', 'RANTTS3', 'RANTTS4', ... % IED, synchronous swoops with spikes on top
    'RINFFS1'}; % marked as bad by Kahana Lab
info.R1128E.refchan = {'all'};

% Line Spectra Info:
info.R1128E.FR1.bsfilt.peak      = [60  179.9 239.8 299.7];
info.R1128E.FR1.bsfilt.halfbandw = [0.5 0.5   0.5   0.7];
info.R1128E.FR1.bsfilt.edge      = 3.1852;

% Bad Segment Info:
info.R1128E.FR1.session(1).badsegment = [240728,241107;278500,278928;339661,340117;366194,366654;377155,377797;457180,457435;462388,462852;472334,473000;487250,487512;751091,751673;778825,779287;811298,811903;851544,852080;856877,857482;945783,947052;1056745,1057354;1059291,1060215;1062937,1063458;1067803,1068927;1081370,1081596;1088020,1089028;1122046,1122559;1211260,1212163;1280042,1280526;1306023,1306692;1571722,1572790;1638470,1638894;1703062,1703764;1710123,1710551;1815353,1816167;1816803,1817247;1819425,1819849;1911358,1911874;1939914,1940656;2038859,2039464;2133429,2133864;2323550,2324143;2331405,2331849;2333257,2333664;2338720,2339212;2341287,2342142;2384541,2384808;2675600,2676282;2676897,2677320;2906172,2906769; 844877,847152;1502497,1507730;1510489,1514484;1659364,1660412;1669905,1670328];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for isubj = 1:length(info.subj)
    subject = info.subj{isubj};

    % Expand bad channel labels.
    info.(subject).badchan.kahana = ft_channelselection(info.(subject).badchan.kahana, info.(subject).allchan.label);
    try
        info.(subject).badchan.broken = ft_channelselection(info.(subject).badchan.broken, info.(subject).allchan.label);
        info.(subject).badchan.epileptic = ft_channelselection(info.(subject).badchan.epileptic, info.(subject).allchan.label);
        info.(subject).badchan.all = unique([info.(subject).badchan.broken; info.(subject).badchan.epileptic; info.(subject).badchan.kahana]);
    catch
        continue
    end
    
    if ismember('FR1', fieldnames(info.(subject))) && ismember('bsfilt', fieldnames(info.(subject).FR1))
        % Calculate bandstop filter edge artifact lengths.
        info.(subject).FR1.bsfilt.edge = util_calculatebandstopedge(info.(subject).FR1.bsfilt.peak, ...
            info.(subject).FR1.bsfilt.halfbandw, ...
            info.(subject).fs);
    end
end

end

% % Get labels of temporal and frontal surface channels.
% info.(subject).surfacechan.all = info.(subject).allchan.label(~strcmpi('d', info.(subject).allchan.type) & ~ismember(info.(subject).allchan.label, info.(subject).badchan.all));
% info.(subject).surfacechan.temporal = info.(subject).allchan.label(~strcmpi('d', info.(subject).allchan.type) & ~ismember(info.(subject).allchan.label, info.(subject).badchan.all) & strcmpi('t', info.(subject).allchan.lobe));
% info.(subject).surfacechan.frontal  = info.(subject).allchan.label(~strcmpi('d', info.(subject).allchan.type) & ~ismember(info.(subject).allchan.label, info.(subject).badchan.all) & strcmpi('f', info.(subject).allchan.lobe));

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

% % Bad Segment Info:


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


% RECONSTRUCT THE LIFECYCLE OF THE EL NINO SOUTHERN OSCILLATION (ENSO) 
% USING DATA-DRIVEN SPECTRAL ANALYSIS OF KOOPMAN/TRANSFER OPERATORS
%
% Modified 2020/03/28

%% DATA SPECIFICATION AND GLOBAL PARAMETERS 
dataset    = 'noaa';           % NOAA 20th Century Reanalysis v2
experiment = 'enso_lifecycle'; % data analysis experiment 
dirName    = '/Volumes/TooMuch/physics/climate/data/noaa'; % input data dir.
fileName   = 'sst.mnmean.v4-4.nc'; % filename base for input data
varName    = 'sst';                % variable name in NetCDF file 

nShiftNino   = 11;        % temporal shift to obtain 2D Nino index
idxPhiEnso   = [ 10 9 ];  % ENSO eigenfunctions from NLSA (kernel operator)
signPhi      = [ -1 -1 ]; % multiplication factor (for consistency with Nino)
idxZEnso     = 9;         % ENSO eigenfunction from generator      
signZ        = -1;        % multiplication factor (for consistency with Nino)
nPhase       = 8;         % number of ENSO phases
nSamplePhase = 100;       % number of samples per phase
phase0       = 5;         % start phase in equivariance plots
leads        = [ 0 6 12 18 24 ]; % leads (in months) for equivariance plots

%% EL NINO/LA NINA EVENTS
% El Nino/La Nina events to mark up in lifecycle plots (in yyyymm format)
ElNinos = { { '201511' '201603' } ... 
            { '199711' '199803' } ...
            { '199111' '199203' } ...
            { '198711' '198803' } ...
            { '198211' '198303' } };

LaNinas = { { '201011' '201103' } ... 
            { '200711' '200803' } ...
            { '199911' '200003' } ...
            { '199811' '199903' } ...
            { '198811' '198903' } };


%% BATCH PROCCESSING
iProc = 1; % index of batch process for this script
nProc = 1; % number of batch processes

%% SCRIPT EXECUTION OPTIONS
ifData    = false; % extract data from NetCDF source files
ifNLSA    = false; % compute kernel (NLSA) eigenfunctions
ifKoopman = false; % compute Koopman eigenfunctions
ifNinoIdx = false; % compute two-dimensional (lead/lag) Nino 3.4 index  
ifNLSALifecycle    = false; % plot ENSO lifecycle from kernel eigenfunctions
ifKoopmanLifecycle = false; % plot ENSO lifecycle from generator eigenfuncs. 
ifNLSAPhases = false; % compute ENSO phases fron kerenel eigenfunctions
ifKoopmanPhases = false; % compute ENSO phases from generator eigenfunctions
ifNLSAEquivariance = true; % make ENSO equivariance plots based on NLSA
ifKoopmanEquivariance = true; % make ENSO equivariance plots based on Koopman

ifPrintFig = true; % print figures to file
%% BUILD NLSA MODEL, DETERMINE BASIC ARRAY SIZES
% In is a data structure containing the NLSA parameters for the training data.
%
% nSE is the number of samples avaiable for data analysis after Takens delay
% embedding.
%
% nSB is the number of samples left out in the start of the time interval (for
% temporal finite differnences employed in the kerenl).
%
% nShiftTakens is the temporal shift applied to align Nino indices with the
% middle of the Takens embedding window eployed in the NLSA kernel. 

disp( 'Building NLSA model...' ); t = tic;
[ model, In ] = climateNLSAModel( dataset, experiment ); 

nSE          = getNTotalSample( model.embComponent );
nSB          = getNXB( model.embComponent );
nShiftTakens = floor( getEmbeddingWindow( model.embComponent ) / 2 );
toc( t )

%% EXTRACT DATA
if ifData
    % Create data structure with input data specifications, and retrieve 
    % input data. Data is saved on disk. 
 
    % Input data
    DataSpecs.In.dir  = dirName;
    DataSpecs.In.file = fileName;
    DataSpecs.In.var  = varName;
    
    % Output data specification
    DataSpecs.Out.dir = fullfile( pwd, 'data/raw', dataset );
    DataSpecs.Out.fld = varName;      

    % Time specification
    DataSpecs.Time.tLim    = { '187001' '201906' }; % time limits
    DataSpecs.Time.tClim   = { '198101' '201012' }; % climatology time limits
    DataSpecs.Time.tStart  = '185401';              % start time in nc file 
    DataSpecs.Time.tFormat = 'yyyymm';              % time format

    % Read SST data for Indo-Pacific domain
    disp( 'Reading Indo-Pacific SST data...' ); t = tic;

    DataSpecs.Domain.xLim = [ 28 290 ]; % longitude limits
    DataSpecs.Domain.yLim = [ -60 20 ]; % latitude limits
    
    DataSpecs.Opts.ifCenter      = false; % don't remove global climatology
    DataSpecs.Opts.ifWeight      = true;  % perform area weighting
    DataSpecs.Opts.ifCenterMonth = false; % don't remove monthly climatology 
    DataSpecs.Opts.ifAverage     = false; % don't perform area averaging
    DataSpecs.Opts.ifNormalize   = false; % don't normalize to unit L2 norm
    DataSpecs.Opts.ifWrite       = true;  % write data to disk

    climateData( dataset, DataSpecs ) % read SST data
    toc( t )

    % Read Nino 3.4 index 
    disp( 'Reading Nino 3.4 data...' ); t = tic; 

    DataSpecs.Domain.xLim = [ 190 240 ]; % longitude limits 
    DataSpecs.Domain.yLim = [ -5 5 ];    % latitude limits

    DataSpecs.Opts.ifCenter      = false; % don't remove global climatology
    DataSpecs.Opts.ifWeight      = true;  % perform area weighting
    DataSpecs.Opts.ifCenterMonth = true;  % remove monthly climatology 
    DataSpecs.Opts.ifAverage     = true;  % perform area averaging
    DataSpecs.Opts.ifNormalize   = false; % don't normalize to unit L2 norm
    DataSpecs.Opts.ifWrite       = true;  % write data to disk

    climateData( dataset, DataSpecs ) % read Nino 3.4 data
    toc( t )
end

%% PERFORM NLSA
if ifNLSA
    
    % Execute NLSA steps. Output from each step is saved on disk

    disp( 'Takens delay embedding...' ); t = tic; 
    computeDelayEmbedding( model )
    toc( t )

    disp( 'Phase space velocity (time tendency of data)...' ); t = tic; 
    computeVelocity( model )
    toc( t )

    fprintf( 'Pairwise distances (%i/%i)...\n', iProc, nProc ); t = tic;
    computePairwiseDistances( model, iProc, nProc )
    toc( t )

    disp( 'Distance symmetrization...' ); t = tic;
    symmetrizeDistances( model )
    toc( t )

    disp( 'Kernel tuning...' ); t = tic;
    computeKernelDoubleSum( model )
    toc( t )

    disp( 'Kernel eigenfunctions...' ); t = tic;
    computeDiffusionEigenfunctions( model )
    toc( t )
end

%% COMPUTE EIGENFUNCTIONS OF KOOPMAN GENERATOR
if ifKoopman
    disp( 'Koopman eigenfunctions...' ); t = tic;
    computeKoopmanEigenfunctions( model )
    toc( t )
end

%% CONSTRUCT TWO-DIMENSIONAL NINO INDEX
% Build a data structure Nino such that:
% 
% Nino.idx is an array of size [ 2 nSE ], where nSE is the number of samples 
% after delay embedding. Nino.idx( 1, : ) contains the values of the Nino 3.4 
% index at the current time. Nino( 2, : ) contains the values of the Nino 3.4 
% index at nShiftNino timesteps (months) in the past.
% 
% Nino.time is an array of size [ 1 nSE ] containing the timestamps in
% Matlab serial date number format. 
if ifNinoIdx

    disp( 'Constructing lagged Nino 3.4 index...' ); t = tic;

    % Timestamps
    Nino.time = getTrgTime( model ); 
    Nino.time = Nino.time( nSB + 1 + nShiftTakens : end );
    Nino.time = Nino.time( 1 : nSE );

    % Nino 3.4 index
    nino = getData( model.trgComponent );
    Nino.idx = [ nino( nShiftNino + 1 : end ) 
                 nino( 1 : end - nShiftNino ) ];
    Nino.idx = Nino.idx( :, nSB + nShiftTakens - nShiftNino + 1 : end );
    Nino.idx = Nino.idx( :, 1 : nSE );
end

%% PLOT ENSO LIFECYCLE BASED ON NLSA EIGENFUNCTIONS
if ifNLSALifecycle

    % Retrieve NLSA eigenfunctions
    phi = getDiffusionEigenfunctions( model );
    Phi.idx = ( signPhi .* phi( :, idxPhiEnso ) )';
    Phi.time = getTrgTime( model );
    Phi.time = Phi.time( nSB + 1 + nShiftTakens : end );
    Phi.time = Phi.time( 1 : nSE );
    
    % Set up figure and axes 
    Fig.units      = 'inches';
    Fig.figWidth   = 8; 
    Fig.deltaX     = .5;
    Fig.deltaX2    = .1;
    Fig.deltaY     = .48;
    Fig.deltaY2    = .3;
    Fig.gapX       = .60;
    Fig.gapY       = .3;
    Fig.gapT       = 0; 
    Fig.nTileX     = 2;
    Fig.nTileY     = 1;
    Fig.aspectR    = 1;
    Fig.fontName   = 'helvetica';
    Fig.fontSize   = 8;
    Fig.tickLength = [ 0.02 0 ];
    Fig.visible    = 'on';
    Fig.nextPlot   = 'add'; 

    [ fig, ax ] = tileAxes( Fig );

    % Plot Nino lifecycle
    set( gcf, 'currentAxes', ax( 1 ) )
    plotLifecycle( Nino, ElNinos, LaNinas, model.tFormat )
    xlabel( 'Nino 3.4' )
    ylabel( sprintf( 'Nino 3.4 - %i months', nShiftNino ) )
    xlim( [ -3 3 ] )
    ylim( [ -3 3 ] )

    % Plot NLSA lifecycle
    set( gcf, 'currentAxes', ax( 2 ) )
    plotLifecycle( Phi, ElNinos, LaNinas, model.tFormat )
    xlabel( sprintf( '\\phi_{%i}', idxPhiEnso( 1 ) ) )
    ylabel( sprintf( '\\phi_{%i}', idxPhiEnso( 2 ) ) )
    xlim( [ -3 3 ] )
    ylim( [ -3 3 ] )
    title( 'Kernel integral operator' )

    % Print figure
    if ifPrintFig
        figFile = 'figEnsoLifecycleKernel.png';
        print( figFile, '-dpng', '-r300' ) 
    end
end

%% PLOT ENSO LIFECYCLE BASED ON KOOPMAN EIGENFUNCTIONS
if ifKoopmanLifecycle

    % Retrieve Koopman eigenfunctions
    z = getKoopmanEigenfunctions( model );
    T = getEigenperiods( model.koopmanOp );
    TEnso = T( idxZEnso ) / 12;
    Z.idx = signZ' .*  [ real( z( :, idxZEnso ) )' 
                         imag( z( :, idxZEnso ) )' ];
    Z.time = getTrgTime( model );
    Z.time = Z.time( nSB + 1 + nShiftTakens : end );
    Z.time = Z.time( 1 : nSE );
    
    % Set up figure and axes 
    Fig.units      = 'inches';
    Fig.figWidth   = 8; 
    Fig.deltaX     = .5;
    Fig.deltaX2    = .1;
    Fig.deltaY     = .48;
    Fig.deltaY2    = .3;
    Fig.gapX       = .60;
    Fig.gapY       = .3;
    Fig.gapT       = 0; 
    Fig.nTileX     = 2;
    Fig.nTileY     = 1;
    Fig.aspectR    = 1;
    Fig.fontName   = 'helvetica';
    Fig.fontSize   = 8;
    Fig.tickLength = [ 0.02 0 ];
    Fig.visible    = 'on';
    Fig.nextPlot   = 'add'; 

    [ fig, ax ] = tileAxes( Fig );

    % Plot Nino lifecycle
    set( gcf, 'currentAxes', ax( 1 ) )
    plotLifecycle( Nino, ElNinos, LaNinas, model.tFormat )
    xlabel( 'Nino 3.4' )
    ylabel( sprintf( 'Nino 3.4 - %i months', nShiftNino ) )
    xlim( [ -3 3 ] )
    ylim( [ -3 3 ] )

    % Plot generator lifecycle
    set( gcf, 'currentAxes', ax( 2 ) )
    plotLifecycle( Z, ElNinos, LaNinas, model.tFormat )
    xlabel( sprintf( 'Re(z_{%i})', idxZEnso ) )
    ylabel( sprintf( 'Im(z_{%i})', idxZEnso ) )
    xlim( [ -2.5 2.5 ] )
    ylim( [ -2.5 2.5 ] )
    title( sprintf( 'Generator; eigenperiod = %1.2f y', TEnso ) )

    % Print figure
    if ifPrintFig
        figFile = 'figEnsoLifecycleGenerator.png';
        print( figFile, '-dpng', '-r300' ) 
    end
end

%% COMPUTE AND PLOT ENSO PHASES BASED ON NLSA EIGENFUNCTIONS
%
% selectIndPhi is a cell array of size [ 1 nPhase ]. selectIndNLSA{ iPhase } 
% is a row vector containing the indices (timestamps) of the data affiliated
% with ENSO phase iPHase. 
%
% anglesPhi is a row vector of size [ 1 nPhase ] containing the polar angles
% in the 2D plane of the phase boundaries.
% 
% avNinoIndPhi is a row vector of size [ 1 nPhase ] containing the average
% Nino 3.4 index for each NLSA phase. 
%
% selectIndNino, anglesNino, and avNinoIndNino are defined analogously to
% selectIndPhi, anglesPhi, and avNinoIndPhi, respectively, using the Nino 3.4
% index. 
if ifNLSAPhases
   
    % Compute ENSO phases based on NLSA
    [ selectIndPhi, anglesPhi, avNinoIndPhi ] = computeLifecyclePhases( ...
        Phi.idx', Nino.idx( 1, : )', nPhase, nSamplePhase );

    % Compute ENSO phases based on Nino 3.4 index
    [ selectIndNino, anglesNino, avNinoIndNino ] = computeLifecyclePhases( ...
        Nino.idx', Nino.idx(1,:)', nPhase, nSamplePhase );
        
    % Set up figure and axes 
    Fig.units      = 'inches';
    Fig.figWidth   = 8; 
    Fig.deltaX     = .5;
    Fig.deltaX2    = .1;
    Fig.deltaY     = .48;
    Fig.deltaY2    = .3;
    Fig.gapX       = .60;
    Fig.gapY       = .3;
    Fig.gapT       = 0; 
    Fig.nTileX     = 2;
    Fig.nTileY     = 1;
    Fig.aspectR    = 1;
    Fig.fontName   = 'helvetica';
    Fig.fontSize   = 8;
    Fig.tickLength = [ 0.02 0 ];
    Fig.visible    = 'on';
    Fig.nextPlot   = 'add'; 

    [ fig, ax ] = tileAxes( Fig );

    % Plot Nino 3.4 phases
    set( gcf, 'currentAxes', ax( 1 ) )
    plotPhases( Nino.idx', selectIndNino, anglesNino ) 
    xlabel( 'Nino 3.4' )
    ylabel( sprintf( 'Nino 3.4 - %i months', nShiftNino ) )
    xlim( [ -3 3 ] )
    ylim( [ -3 3 ] )

    % Plot NLSA phases
    set( gcf, 'currentAxes', ax( 2 ) )
    plotPhases( Phi.idx', selectIndPhi, anglesPhi )
    xlabel( sprintf( '\\phi_{%i}', idxPhiEnso( 1 ) ) )
    ylabel( sprintf( '\\phi_{%i}', idxPhiEnso( 2 ) ) )
    xlim( [ -3 3 ] )
    ylim( [ -3 3 ] )
    title( 'Kernel integral operator' )

    % Print figure
    if ifPrintFig
        figFile = 'figEnsoPhasesKernel.png';
        print( figFile, '-dpng', '-r300' ) 
    end

end

%% COMPUTE AND PLOT ENSO PHASES BASED ON GENERATOR EIGENFUNCTIONS
%
% selectIndZ is a cell array of size [ 1 nPhase ]. selectIndZ{ iPhase } 
% is a row vector containing the indices (timestamps) of the data affiliated
% with ENSO phase iPHase. 
%
% anglesZ is a row vector of size [ 1 nPhase ] containing the polar angles
% in the 2D plane of the phase boundaries.
% 
% avNinoIndZ is a row vector of size [ 1 nPhase ] containing the average
% Nino 3.4 index for each NLSA generator. 
%
% selectIndNino, anglesNino, and avNinoIndNino are defined analogously to
% selectIndZ, anglesZ, and avNinoIndZ, respectively, using the Nino 3.4
% index. 
if ifKoopmanPhases
   
    % Compute ENSO phases based on generator
    [ selectIndZ, anglesZ, avNinoIndZ ] = computeLifecyclePhases( ...
        Z.idx', Nino.idx( 1, : )', nPhase, nSamplePhase );

    % Compute ENSO phases based on Nino 3.4 index
    [ selectIndNino, anglesNino, avNinoIndNino ] = computeLifecyclePhases( ...
        Nino.idx', Nino.idx(1,:)', nPhase, nSamplePhase );
        
    % Set up figure and axes 
    Fig.units      = 'inches';
    Fig.figWidth   = 8; 
    Fig.deltaX     = .5;
    Fig.deltaX2    = .1;
    Fig.deltaY     = .48;
    Fig.deltaY2    = .3;
    Fig.gapX       = .60;
    Fig.gapY       = .3;
    Fig.gapT       = 0; 
    Fig.nTileX     = 2;
    Fig.nTileY     = 1;
    Fig.aspectR    = 1;
    Fig.fontName   = 'helvetica';
    Fig.fontSize   = 8;
    Fig.tickLength = [ 0.02 0 ];
    Fig.visible    = 'on';
    Fig.nextPlot   = 'add'; 

    [ fig, ax ] = tileAxes( Fig );

    % Plot Nino 3.4 phases
    set( gcf, 'currentAxes', ax( 1 ) )
    plotPhases( Nino.idx', selectIndNino, anglesNino ) 
    xlabel( 'Nino 3.4' )
    ylabel( sprintf( 'Nino 3.4 - %i months', nShiftNino ) )
    xlim( [ -3 3 ] )
    ylim( [ -3 3 ] )

    % Plot generator phases
    set( gcf, 'currentAxes', ax( 2 ) )
    plotPhases( Z.idx', selectIndZ, anglesZ )
    xlabel( sprintf( 'Re(z_{%i})', idxZEnso ) )
    ylabel( sprintf( 'Im(z_{%i})', idxZEnso ) )
    xlim( [ -2.5 2.5 ] )
    ylim( [ -2.5 2.5 ] )
    title( sprintf( 'Generator; eigenperiod = %1.2f y', TEnso ) )

    % Print figure
    if ifPrintFig
        figFile = 'figEnsoPhasesKoopman.png';
        print( figFile, '-dpng', '-r300' ) 
    end


end

%% EQUIVARIANCE PLOTS BASED ON NLSA
if ifNLSAEquivariance

    nLead = numel( leads );  

    % Set up figure and axes 
    Fig.units      = 'inches';
    Fig.figWidth   = 10; 
    Fig.deltaX     = .5;
    Fig.deltaX2    = .1;
    Fig.deltaY     = .48;
    Fig.deltaY2    = .5;
    Fig.gapX       = .20;
    Fig.gapY       = .5;
    Fig.gapT       = .25; 
    Fig.nTileX     = nLead;
    Fig.nTileY     = 2;
    Fig.aspectR    = 1;
    Fig.fontName   = 'helvetica';
    Fig.fontSize   = 6;
    Fig.tickLength = [ 0.02 0 ];
    Fig.visible    = 'on';
    Fig.nextPlot   = 'add'; 

    [ fig, ax, axTitle ] = tileAxes( Fig );

    % Loop over the leads
    for iLead = 1 : numel( leads )

        % Plot Nino 3.4 phases
        set( gcf, 'currentAxes', ax( iLead, 1 ) )
        plotPhaseEvolution( Nino.idx', selectIndNino, anglesNino, ...
                            phase0, leads( iLead ) ) 
        xlabel( 'Nino 3.4' )
        xlim( [ -3 3 ] )
        ylim( [ -3 3 ] )
        if iLead > 1 
            yticklabels( [] )
        else
            ylabel( sprintf( 'Nino 3.4 - %i months', nShiftNino ) )
        end
        title( sprintf( 'Lead = %i months', leads( iLead ) ) )
        
        % Plot NLSA phases 
        set( gcf, 'currentAxes', ax( iLead, 2 ) )
        plotPhaseEvolution( Phi.idx', selectIndPhi, anglesPhi, ...
                            phase0, leads( iLead ) )
        xlabel( sprintf( '\\phi_{%i}', idxPhiEnso( 1 ) ) )
        if iLead > 1
            yticklabels( [] )
        else
            ylabel( sprintf( '\\phi_{%i}', idxPhiEnso( 2 ) ) )
        end
        xlim( [ -3 3 ] )
        ylim( [ -3 3 ] )
    end

    title( axTitle, sprintf( 'Start phase = %i', phase0 ) )

    % Print figure
    if ifPrintFig
        figFile = sprintf( 'figEnsoEquivarianceKernel_phase%i.png', phase0 );
        print( figFile, '-dpng', '-r300' ) 
    end
end

%% EQUIVARIANCE PLOTS BASED ON GENERATOR
if ifKoopmanEquivariance

    nLead = numel( leads );  

    % Set up figure and axes 
    Fig.units      = 'inches';
    Fig.figWidth   = 10; 
    Fig.deltaX     = .5;
    Fig.deltaX2    = .1;
    Fig.deltaY     = .48;
    Fig.deltaY2    = .5;
    Fig.gapX       = .20;
    Fig.gapY       = .5;
    Fig.gapT       = .25; 
    Fig.nTileX     = nLead;
    Fig.nTileY     = 2;
    Fig.aspectR    = 1;
    Fig.fontName   = 'helvetica';
    Fig.fontSize   = 6;
    Fig.tickLength = [ 0.02 0 ];
    Fig.visible    = 'on';
    Fig.nextPlot   = 'add'; 

    [ fig, ax, axTitle ] = tileAxes( Fig );

    % Loop over the leads
    for iLead = 1 : numel( leads )

        % Plot Nino 3.4 phases
        set( gcf, 'currentAxes', ax( iLead, 1 ) )
        plotPhaseEvolution( Nino.idx', selectIndNino, anglesNino, ...
                            phase0, leads( iLead ) ) 
        xlabel( 'Nino 3.4' )
        xlim( [ -3 3 ] )
        ylim( [ -3 3 ] )
        if iLead > 1 
            yticklabels( [] )
        else
            ylabel( sprintf( 'Nino 3.4 - %i months', nShiftNino ) )
        end
        title( sprintf( 'Lead = %i months', leads( iLead ) ) )
        
        % Plot Koopman phases 
        set( gcf, 'currentAxes', ax( iLead, 2 ) )
        plotPhaseEvolution( Z.idx', selectIndZ, anglesZ, ...
                            phase0, leads( iLead ) )
        xlabel( sprintf( 'Re(z_{%i})', idxZEnso ) )
        if iLead > 1
            yticklabels( [] )
        else
            ylabel( sprintf( 'Im(z_{%i})', idxZEnso ) )
        end
        xlim( [ -2.5 2.5 ] )
        ylim( [ -2.5 2.5 ] )
    end

    title( axTitle, sprintf( 'Start phase = %i', phase0 ) )

    % Print figure
    if ifPrintFig
        figFile = sprintf( 'figEnsoEquivarianceGenerator_phase%i.png', phase0);
        print( figFile, '-dpng', '-r300' ) 
    end
end



% AUXILIARY FUNCTIONS

%% Function to plot two-dimensional ENSO index, highlighting significant events
function plotLifecycle( Index, Ninos, Ninas, tFormat )

% plot temporal evolution of index
plot( Index.idx( 1, : ), Index.idx( 2, : ), 'g-' )
hold on
grid on

% highlight significant events
for iENSO = 1 : numel( Ninos )

    % Serial date numbers for start and end of event
    tLim = datenum( Ninos{ iENSO }( 1 : 2 ), tFormat );
    
    % Find and plot portion of index time series
    idxT1     = find( Index.time == tLim( 1 ) );
    idxT2     = find( Index.time == tLim( 2 ) );
    idxTLabel = round( ( idxT1 + idxT2 ) / 2 ); 
    plot( Index.idx( 1, idxT1 : idxT2 ), Index.idx( 2, idxT1 : idxT2 ), ...
          'r-', 'lineWidth', 2 )
    text( Index.idx( 1, idxTLabel ), Index.idx( 2, idxTLabel ), ...
          datestr( Index.time( idxT2 ), 'yyyy' ) )
end
for iENSO = 1 : numel( Ninas )

    % Serial date numbers for start and end of event
    tLim = datenum( Ninas{ iENSO }( 1 : 2 ), tFormat );
    
    % Find and plot portion of index time series
    idxT1 = find( Index.time == tLim( 1 ) );
    idxT2 = find( Index.time == tLim( 2 ) );
    idxTLabel = round( ( idxT1 + idxT2 ) / 2 ); 
    plot( Index.idx( 1, idxT1 : idxT2 ), Index.idx( 2, idxT1 : idxT2 ), ...
          'b-', 'lineWidth', 2 )
    text( Index.idx( 1, idxTLabel ), Index.idx( 2, idxTLabel ), ...
          datestr( Index.time( idxT2 ), 'yyyy' ) )
end

end

%% Function to plot two-dimensional ENSO index and associated phases
function plotPhases( index, selectInd, angles )

% plot temporal evolution of index
plot( index( :, 1 ), index( :, 2 ), '-', 'Color', [ 1 1 1 ] * .7  )
hold on

% plot phases
nPhase = numel( selectInd );
c = distinguishable_colors( nPhase );
c = c( [ 2 3 4 5 1 6 7 8 ], : );
for iPhase = 1 : nPhase

    plot( index( selectInd{ iPhase }, 1 ), index( selectInd{ iPhase }, 2 ), ...
        '.', 'markersize', 15, 'color', c( iPhase, : ) )
end

end

%% Function to plot ENSO phase evolution
function plotPhaseEvolution( index, selectInd, angles, phase0, lead )

% plot temporal evolution of index
plot( index( :, 1 ), index( :, 2 ), '-', 'Color', [ 1 1 1 ] * .7  )
hold on

% plot phases
nPhase = numel( selectInd );
c = distinguishable_colors( nPhase );
c = c( [ 2 3 4 5 1 6 7 8 ], : );
for iPhase = 1 : nPhase

    plot( index( selectInd{ iPhase }, 1 ), index( selectInd{ iPhase }, 2 ), ...
        '.', 'markersize', 5, 'color', c( iPhase, : ) * .7 )
end

% plot evolution from reference phase
indMax = size( index, 1 );
ind = selectInd{ phase0 } + lead; 
ind = ind( ind <= indMax );
plot( index( ind, 1 ), index( ind, 2 ), ...
    '.', 'markersize', 10, 'color', c( phase0, : ) )   
end

#include"cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !MODULE: gotm --- the general framework \label{sec:gotm}
!
! !INTERFACE:
   module gotm
!
! !DESCRIPTION:
! This is 'where it all happens'. This module provides the internal
! routines {\tt init\_gotm()} to initialise the whole model and
! {\tt time\_loop()} to manage the time-stepping of all fields. These
! two routines in turn call more specialised routines e.g.\ of the
! {\tt meanflow} and {\tt turbulence} modules to delegate the job.
!
!  Here is also the place for a few words on FORTRAN `units' we used.
!  The method of FORTRAN units is quite rigid and also a bit dangerous,
!  but lacking a better alternative we adopted it here. This requires
!  the definition of ranges of units for different purposes. In GOTM
!  we strongly suggest to use units according to the following
!  conventions.
!  \begin{itemize}
!     \item unit=10 is reserved for reading namelists.
!     \item units 20-29 are reserved for the {\tt airsea} module.
!     \item units 30-39 are reserved for the {\tt meanflow} module.
!     \item units 40-49 are reserved for the {\tt turbulence} module.
!     \item units 50-59 are reserved for the {\tt output} module.
!     \item units 60-69 are reserved for the {\tt extra} modules
!           like those dealing with sediments or sea-grass.
!     \item units 70- are \emph{not} reserved and can be used as you
!           wish.
!  \end{itemize}
!
! !USES:
   use field_manager
   use register_all_variables, only: do_register_all_variables, fm
   use output_manager_core, only:output_manager_host=>host, type_output_manager_host=>type_host,type_output_manager_file=>type_file,time_unit_second,type_output_category
   use output_manager
   use diagnostics

   use meanflow
   use input
   use observations
   use time

   use airsea,      only: init_air_sea,do_air_sea,clean_air_sea
   use airsea,      only: set_sst,set_ssuv,integrated_fluxes
   use airsea,      only: calc_fluxes
   use airsea,      only: wind=>w,tx,ty,I_0,cloud,heat,precip,evap,airp
   use airsea,      only: bio_albedo,bio_drag_scale
   use airsea_variables, only: qa,ta

   use turbulence,  only: turb_method
   use turbulence,  only: init_turbulence,do_turbulence
   use turbulence,  only: num,nuh,nus
!RRH: vvv
   use turbulence,  only: nucl
!RRH: ^^^
   use turbulence,  only: const_num,const_nuh
   use turbulence,  only: gamu,gamv,gamh,gams
   use turbulence,  only: kappa
   use turbulence,  only: clean_turbulence

   use langmuir,    only: init_langmuir
   use kpp,         only: init_kpp,do_kpp,clean_kpp
   use zdfosm,         only: init_osm,do_osm,clean_osm
   use EPBL_gotm, only: epbl_gotm_init, epbl_gotm_interface

   use mtridiagonal,only: init_tridiagonal,clean_tridiagonal
   use eqstate,     only: init_eqstate

#ifdef SEAGRASS
   use seagrass
#endif
#ifdef SPM
   use spm_var, only: spm_calc
   use spm, only: init_spm, set_env_spm, do_spm, end_spm
#endif
#ifdef _FABM_
   use gotm_fabm,only:init_gotm_fabm,init_gotm_fabm_state,set_env_gotm_fabm,do_gotm_fabm,clean_gotm_fabm,fabm_calc
   use gotm_fabm,only:model_fabm=>model,standard_variables_fabm=>standard_variables
   use gotm_fabm_input,only:init_gotm_fabm_input
#endif

   IMPLICIT NONE
   private
!
! !PUBLIC MEMBER FUNCTIONS:
   public init_gotm, time_loop, clean_up

!
! !DEFINED PARAMETERS:
   integer, parameter                  :: namlst=10
#ifdef SEAGRASS
   integer, parameter                  :: unit_seagrass=62
#endif
#ifdef SPM
   integer, parameter                  :: unit_spm=64
#endif
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard
!
!EOP
!
!  private data members initialised via namelists
   character(len=80)         :: title
   integer                   :: nlev
   REALTYPE                  :: dt
   REALTYPE                  :: cnpar
   integer                   :: buoy_method
!  station description
   character(len=80)         :: name
   REALTYPE,target           :: latitude,longitude

   type,extends(type_output_manager_host) :: type_gotm_host
   contains
      procedure :: julian_day => gotm_host_julian_day
      procedure :: calendar_date => gotm_host_calendar_date
   end type
!
!-----------------------------------------------------------------------

   contains

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: Initialise the model \label{initGOTM}
!
! !INTERFACE:
   subroutine init_gotm()
!
! !DESCRIPTION:
!  This internal routine triggers the initialization of the model.
!  The first section reads the namelists of {\tt gotmrun.nml} with
!  the user specifications. Then, one by one each of the modules are
!  initialised with help of more specialised routines like
!  {\tt init\_meanflow()} or {\tt init\_turbulence()} defined inside
!  their modules, respectively.
!
!  Note that the KPP-turbulence model requires not only a call to
!  {\tt init\_kpp()} but before also a call to {\tt init\_turbulence()},
!  since there some fields (fluxes, diffusivities, etc) are declared and
!  the turbulence namelist is read.

! !USES:
  IMPLICIT NONE
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard
!
!EOP
!
! !LOCAL VARIABLES:
   namelist /model_setup/ title,nlev,dt,cnpar,buoy_method
   namelist /station/     name,latitude,longitude,depth
   namelist /time/        timefmt,MaxN,start,stop
   logical          ::    list_fields=.false.
   integer          ::    rc, k
   logical          ::    file_exists
!-----------------------------------------------------------------------
!BOC
   LEVEL1 'init_gotm'
   STDERR LINE

!  The sea surface elevation (zeta) and vertical advection method (w_adv_method)
!  will be set by init_observations.
!  However, before that happens, it is already used in updategrid.
!  therefore, we set to to a reasonable default here.
   zeta = _ZERO_
   w_adv_method = 0

!  open the namelist file.
   LEVEL2 'reading model setup namelists..'
   open(namlst,file='gotmrun.nml',status='old',action='read',err=90)

   read(namlst,nml=model_setup,err=91)
   read(namlst,nml=station,err=92)
   read(namlst,nml=time,err=93)

   ! Initialize field manager
   call fm%register_dimension('lon',1,id=id_dim_lon)
   call fm%register_dimension('lat',1,id=id_dim_lat)
   call fm%register_dimension('z',nlev,id=id_dim_z)
   call fm%register_dimension('zi',nlev+1,id=id_dim_zi)
   call fm%register_dimension('time',id=id_dim_time)
   call fm%initialize(prepend_by_default=(/id_dim_lon,id_dim_lat/),append_by_default=(/id_dim_time/))

   allocate(type_gotm_host::output_manager_host)
   call output_manager_init(fm,title)

   inquire(file='output.yaml',exist=file_exists)
   if (.not.file_exists) then
      call deprecated_output(namlst,title,dt,list_fields)
   end if

   LEVEL2 'done.'

!  initialize a few things from  namelists
   timestep   = dt
   depth0     = depth

!  write information for this run
   LEVEL2 trim(title)
   LEVEL2 'Using ',nlev,' layers to resolve a depth of',depth
   LEVEL2 'The station ',trim(name),' is situated at (lat,long) ',      &
           latitude,longitude
   LEVEL2 trim(name)

   LEVEL2 'initializing modules....'
   call init_input(nlev)
   call init_time(MinN,MaxN)
   call init_eqstate(namlst)
   close (namlst)

!  From here - each init_? is responsible for opening and closing the
!  namlst - unit.
   call init_meanflow(namlst,'gotmmean.nml',nlev,latitude)
   call init_tridiagonal(nlev)
   call updategrid(nlev,dt,zeta)

!  initialise each of the extra features/modules
#ifdef SEAGRASS
   call init_seagrass(namlst,'seagrass.nml',unit_seagrass,nlev,h,fm)
#endif
#ifdef SPM
   call init_spm(namlst,'spm.nml',unit_spm,nlev)
#endif
   call init_observations(namlst,'obs.nml',julianday,secondsofday,      &
                          depth,nlev,z,h,gravity,rho_0)
   call get_all_obs(julianday,secondsofday,nlev,z)

!  Call do_input to make sure observed profiles are up-to-date.
   call do_input(julianday,secondsofday,nlev,z)
!  read wave spectrum
   call do_input_spec(julianday,secondsofday,nfreq,wav_freq)

   !  Update the grid based on true initial zeta (possibly read from file by do_input).
   call updategrid(nlev,dt,zeta)

!  calculate Stokes drift
!  should be after update grid
   call stokes_drift(wav_freq,wav_spec,wav_xcmp,wav_ycmp,nlev,z,zi,us_x,us_y,delta,ustokes,vstokes,dusdz,dvsdz)

   call init_turbulence(namlst,'gotmturb.nml',nlev)

!  initialize Langmuir
   call init_langmuir(namlst,'langmuir.nml')

!  initialise mean fields
   s = sprof
   t = tprof
   u = uprof
   v = vprof

!  initialize OSMOSIS model
   if (turb_method.eq.98) then
      call init_osm(namlst,'osm.nml',nlev,depth,h)
   endif

!  initialize KPP model
   if (turb_method.eq.99) then
      call init_kpp(namlst,'kpp.nml',nlev,depth,h,gravity,rho_0)
   endif

   ! Initialize EPBL/JHL Model
   if (turb_method.eq.100) then
      call epbl_gotm_init(nlev,namlst)
   endif

   call init_air_sea(namlst,latitude,longitude)

   call do_register_all_variables(latitude,longitude,nlev)
!   call init_output(title,nlev,latitude,longitude)

!  initialize FABM module
#ifdef _FABM_

!  Initialize the GOTM-FABM coupler from its configuration file.
   call init_gotm_fabm(nlev,namlst,'gotm_fabm.nml',dt,fm)

!  Link relevant GOTM data to FABM.
!  This sets pointers, rather than copying data, and therefore needs to be done only once.
   if (fabm_calc) then
      call model_fabm%link_horizontal_data(standard_variables_fabm%bottom_depth,depth)
      call model_fabm%link_horizontal_data(standard_variables_fabm%bottom_depth_below_geoid,depth0)
      call model_fabm%link_horizontal_data(standard_variables_fabm%bottom_roughness_length,z0b)
      if (calc_fluxes) then
         call model_fabm%link_horizontal_data(standard_variables_fabm%surface_specific_humidity,qa)
         call model_fabm%link_horizontal_data(standard_variables_fabm%surface_air_pressure,airp)
         call model_fabm%link_horizontal_data(standard_variables_fabm%surface_temperature,ta)
      end if
   end if
   call set_env_gotm_fabm(latitude,longitude,dt,w_adv_method,w_adv_discr,t(1:nlev),s(1:nlev),rho(1:nlev), &
                          nuh,h,w,bioshade(1:nlev),I_0,cloud,taub,wind,precip,evap,z(1:nlev), &
                          A,g1,g2,yearday,secondsofday,SRelaxTau(1:nlev),sProf(1:nlev), &
                          bio_albedo,bio_drag_scale)

!  Initialize FABM input (data files with observations)
   call init_gotm_fabm_input(namlst,'fabm_input.nml',nlev,h(1:nlev))
#endif

! TODO: Why call do_input again? <19-12-17, Qing Li> !
   call do_input(julianday,secondsofday,nlev,z)

!  reset some quantities, added by Peng Wang, UCLA
   tx = tx/rho_0
   ty = ty/rho_0

!  Call stratification to make sure density has sensible value.
!  This is needed to ensure the initial density is saved correctly, and also for FABM.
   call stratification(nlev,buoy_method,dt,cnpar,nuh,gamh)

#ifdef _FABM_

   if (fabm_calc) then
!     Initialize FABM initial state (this is done after the first call to do_input,
!     to allow user-specified observed values to be used as initial state)
      call init_gotm_fabm_state(nlev)
   end if

#endif

   if (list_fields) call fm%list()

   LEVEL2 'done.'
   STDERR LINE

#ifdef _PRINTSTATE_
   call print_state
#endif

   return

90 FATAL 'I could not open gotmrun.nml for reading'
   stop 'init_gotm'
91 FATAL 'I could not read the "model_setup" namelist'
   stop 'init_gotm'
92 FATAL 'I could not read the "station" namelist'
   stop 'init_gotm'
93 FATAL 'I could not read the "time" namelist'
   stop 'init_gotm'
   end subroutine init_gotm
!EOC

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: Manage global time--stepping \label{timeLoop}
!
! !INTERFACE:
   subroutine time_loop()
!
! !DESCRIPTION:
! This internal routine is the heart of the code. It contains
! the main time-loop inside of which all routines required
! during the time step are called. The following main processes are
! successively triggered.
! \begin{enumerate}
!  \item The model time is updated and the output is prepared.
!  \item Air-sea interactions (flux, SST) are computed.
!  \item The time step is performed on the mean-flow equations
!        (momentum, temperature).
!  \item Some quantities related to shear and stratification are updated
!        (shear-number, buoyancy frequency, etc).
!  \item Turbulence is updated depending on what turbulence closure
!        model has been specified by the user.
!  \item The results are written to the output files.
! \end{enumerate}
!
! Depending on macros set for the Fortran pre-processor, extra features
! like the effects of sea-grass or sediments are considered in this routine
! (see \sect{sec:extra}).
!
! !USES:
   IMPLICIT NONE
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard
!
!EOP
!
! !LOCAL VARIABLES:
   integer(kind=timestepkind):: n,progress
   integer                   :: i

   REALTYPE                  :: tFlux,btFlux,sFlux,bsFlux
   REALTYPE                  :: tRad(0:nlev),bRad(0:nlev)
   character(8)              :: d_
   character(10)             :: t_

!
!-----------------------------------------------------------------------
!BOC
   LEVEL1 'saving initial conditions'
   call output_manager_save(julianday,int(fsecondsofday),int(mod(fsecondsofday,_ONE_)*1000000),0)
   STDERR LINE
   LEVEL1 'time_loop'
   progress = (MaxN-MinN+1)/10
   i=0
   do n=MinN,MaxN

      if(mod(n,progress) .eq. 0 .or. n .eq. MinN) then
#if 0
         call date_and_time(date=d_,time=t_)
         LEVEL0 i,'%: ',t_(1:2),':',t_(3:4),':',t_(5:10)
#else
         LEVEL0 i,'%'
#endif
         i = i +10
      end if

!     prepare time and output
      call update_time(n)

!     all observations/data
      call do_input(julianday,secondsofday,nlev,z)
      call get_all_obs(julianday,secondsofday,nlev,z)

!     update wave spectrum
      call do_input_spec(julianday,secondsofday,nfreq,wav_freq)

!     external forcing
      if( calc_fluxes ) then
         call set_sst(T(nlev))
         call set_ssuv(u(nlev),v(nlev))
      end if
      call do_air_sea(julianday,secondsofday)

!     reset some quantities
      tx = tx/rho_0
      ty = ty/rho_0

      call integrated_fluxes(dt)

!     meanflow integration starts
      call updategrid(nlev,dt,zeta)

!     update Stokes drift
!     should be after updategrid
      call stokes_drift(wav_freq,wav_spec,wav_xcmp,wav_ycmp,nlev,z,zi,us_x,us_y,delta,ustokes,vstokes,dusdz,dvsdz)

      call wequation(nlev,dt)
      call coriolis(nlev,dt)

!     update velocity
!RRH: vvv
!     call uequation(nlev,dt,cnpar,tx,num,gamu,ext_press_mode)
!     call vequation(nlev,dt,cnpar,ty,num,gamv,ext_press_mode)
#if defined(STOKESFLUX)
      call uequation_stokesflux(nlev,dt,cnpar,tx,num,nucl,dusdz,gamu,ext_press_mode)
      call vequation_stokesflux(nlev,dt,cnpar,ty,num,nucl,dvsdz,gamv,ext_press_mode)
#else
      call uequation(nlev,dt,cnpar,tx,num,gamu,ext_press_mode)
      call vequation(nlev,dt,cnpar,ty,num,gamv,ext_press_mode)
#endif
!RRH: ^^^
      call extpressure(ext_press_mode,nlev)
      call intpressure(nlev)
      call friction(kappa,avmolu,tx,ty)

#ifdef SEAGRASS
      if(seagrass_calc) call do_seagrass(nlev,dt)
#endif

!     update temperature and salinity
      if (s_prof_method .ne. 0) then
         call salinity(nlev,dt,cnpar,nus,gams)
      endif

      if (t_prof_method .ne. 0) then
         call temperature(nlev,dt,cnpar,I_0,heat,nuh,gamh,rad)
      endif

!     update shear and stratification
      call shear(nlev,cnpar)
      call stratification(nlev,buoy_method,dt,cnpar,nuh,gamh)

#ifdef SPM
      if (spm_calc) then
         call set_env_spm(nlev,rho_0,depth,u_taub,h,u,v,nuh, &
                          tx,ty,Hs,Tz,Phiw)
         call do_spm(nlev,dt)
      end if
#endif
#ifdef _FABM_
      call do_gotm_fabm(nlev,real(n,kind(_ONE_)))
#endif

!    compute turbulent mixing
      select case (turb_method)
      case (0)
!        do convective adjustment
         call convectiveadjustment(nlev,num,nuh,const_num,const_nuh,    &
                                   buoy_method,gravity,rho_0)
      case (98)
!        update OSMOSIS model
         call convert_fluxes(nlev,gravity,cp,rho_0,heat,precip+evap,    &
                             rad,T,S,tFlux,sFlux,btFlux,bsFlux,tRad,bRad)
         call do_osm(nlev,depth,h,dt)
      case (99)
!        update KPP model
         call convert_fluxes(nlev,gravity,cp,rho_0,heat,precip+evap,    &
                             rad,T,S,tFlux,sFlux,btFlux,bsFlux,tRad,bRad)

         call do_kpp(nlev,depth,h,rho,u,v,T,S,NN,NNT,NNS,SS,            &
                     u_taus,u_taub,tFlux,btFlux,sFlux,bsFlux,           &
                     tRad,bRad,cori)
      case (100)
!        update EPBL model
         call convert_fluxes(nlev,gravity,cp,rho_0,heat,precip+evap,    &
              rad,T,S,tFlux,sFlux,btFlux,bsFlux,tRad,bRad)
         call epbl_gotm_interface(nlev,h,u,v,T,S,&
              u_taus,u_taub,tFlux,btFlux,sFlux,&
              bsFlux,tRad,bRad,cori, dt)

      case default
!        update one-point models
# ifdef SEAGRASS
         call do_turbulence(nlev,dt,depth,u_taus,u_taub,z0s,z0b,h,      &
                            NN,SS,CSSTK,SSSTK,xP)
# else
         call do_turbulence(nlev,dt,depth,u_taus,u_taub,z0s,z0b,h,      &
                            NN,SS,CSSTK,SSSTK)
# endif
      end select

      call do_diagnostics(nlev)
      call output_manager_save(julianday,int(fsecondsofday),int(mod(fsecondsofday,_ONE_)*1000000),int(n))

   end do
   STDERR LINE

   return
   end subroutine time_loop
!EOC

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: The run is over --- now clean up.
!
! !INTERFACE:
   subroutine clean_up()
!
! !DESCRIPTION:
! This function is just a wrapper for the external routine
! {\tt close\_output()} discussed in \sect{sec:output}. All open files
! will be closed after this call.
!
! !USES:
   IMPLICIT NONE
!
! !REVISION HISTORY:
!  Original author(s): Karsten Bolding & Hans Burchard
!
!EOP
!-----------------------------------------------------------------------
!BOC
#ifdef _PRINTSTATE_
   call print_state
#endif

   LEVEL1 'clean_up'

   call clean_air_sea()

   call clean_meanflow()

   if (turb_method.eq.98) call clean_osm()

   if (turb_method.eq.99) call clean_kpp()

   call clean_turbulence()

   call clean_observations()

   call clean_tridiagonal()

#ifdef SEAGRASS
   call end_seagrass
#endif

#ifdef _FABM_
   call clean_gotm_fabm()
#endif

   call close_input()

   call output_manager_clean()

   call fm%finalize()

   return
   end subroutine clean_up
!EOC

#ifdef _PRINTSTATE_
!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE: Print the current state of all loaded gotm modules.
!
! !INTERFACE:
   subroutine print_state()
!
! !DESCRIPTION:
!  This routine writes the value of all module-level variables to screen.
!
! !USES:
   use airsea,    only: print_state_airsea
   use turbulence,only: print_state_turbulence

   IMPLICIT NONE
!
! !REVISION HISTORY:
!  Original author(s): Jorn Bruggeman
!
!EOP
!-----------------------------------------------------------------------
!BOC
   LEVEL1 'state of gotm module'
   LEVEL2 'title',title
   LEVEL2 'nlev',nlev
   LEVEL2 'dt',dt
   LEVEL2 'cnpar',cnpar
   LEVEL2 'buoy_method',buoy_method
   LEVEL2 'name',name
   LEVEL2 'latitude',latitude
   LEVEL2 'longitude',longitude

   call print_state_time
   call print_state_meanflow
   call print_state_observations
   call print_state_airsea
   call print_state_turbulence
   call print_state_bio

   end subroutine print_state
!EOC
#endif

   subroutine gotm_host_julian_day(self,yyyy,mm,dd,julian)
      class (type_gotm_host), intent(in) :: self
      integer, intent(in)  :: yyyy,mm,dd
      integer, intent(out) :: julian
      call julian_day(yyyy,mm,dd,julian)
   end subroutine

   subroutine gotm_host_calendar_date(self,julian,yyyy,mm,dd)
      class (type_gotm_host), intent(in) :: self
      integer, intent(in)  :: julian
      integer, intent(out) :: yyyy,mm,dd
      call calendar_date(julian,yyyy,mm,dd)
   end subroutine

!-----------------------------------------------------------------------

   end module gotm

!-----------------------------------------------------------------------
! Copyright by the GOTM-team under the GNU Public License - www.gnu.org
!-----------------------------------------------------------------------

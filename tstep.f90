!> \file tstep.f90
!!  Performs the time integration

!>
!!  Performs the time integration
!>
!! Tstep uses adaptive timestepping and 3rd order Runge Kutta time integration.
!! The adaptive timestepping chooses it's delta_t according to the courant number
!! and the cell peclet number, depending on the advection scheme in use.
!!
!!
!!  \author Chiel van Heerwaarden, Wageningen University
!!  \author Thijs Heus,MPI-M
!! \see Wicker and Skamarock 2002
!!  \par Revision list
!  This file is part of DALES.
!
! DALES is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! DALES is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.
!
!  Copyright 1993-2009 Delft University of Technology, Wageningen University, Utrecht University, KNMI
!

!> Determine time step size dt in initialization and update time variables
!!
!! The size of the timestep Delta t is determined adaptively, and is limited by both the Courant-Friedrichs-Lewy criterion CFL
!! \latexonly
!! \begin{equation}
!! \CFL = \mr{max}\left(\left|\frac{u_i \Delta t}{\Delta x_i}\right|\right),
!! \end{equation}
!! and the diffusion number $d$. The timestep is further limited by the needs of other modules, e.g. the statistics.
!! \endlatexonly
subroutine tstep_update


  use modglobal, only : i1,j1,rk3step,timee,rtimee,dtmax,dt,ntimee,ntrun,courant,peclet,&
                        kmax,dx,dy,dzh,dt_lim,ladaptive,timeleft,idtmax,rdt,tres,longint ,lwarmstart
  use modfields, only : um,vm,wm
  use modsubgrid,only : ekm
  use modmpi,    only : comm3d,mpierr,mpi_max,my_real
  implicit none

  real, allocatable, dimension (:) :: courtotl,courtot
  integer       :: k
  real,save     :: courtotmax=-1,peclettot=-1
  real          :: courold,peclettotl,pecletold
  logical,save  :: spinup=.true.

  allocate(courtotl(kmax),courtot(kmax))

  if(lwarmstart) spinup = .false.

  rk3step = mod(rk3step,3) + 1
  if(rk3step == 1) then
    ! Initialization
    if (spinup) then
      if (ladaptive) then
        courold = courtotmax
        pecletold = peclettot
        peclettotl=0.0
        do k=1,kmax
          courtotl(k)=maxval(um(2:i1,2:j1,k)*um(2:i1,2:j1,k)/(dx*dx)+vm(2:i1,2:j1,k)*vm(2:i1,2:j1,k)/(dy*dy)+&
          wm(2:i1,2:j1,k)*wm(2:i1,2:j1,k)/(dzh(k)*dzh(k)))*rdt*rdt
        end do
        call MPI_ALLREDUCE(courtotl,courtot,kmax,MY_REAL,MPI_MAX,comm3d,mpierr)
        courtotmax=0.0
        do k=1,kmax
          courtotmax=max(courtotmax,courtot(k))
        enddo
        courtotmax=sqrt(courtotmax)
        do k=1,kmax
          peclettotl=max(peclettotl,maxval(ekm(2:i1,2:j1,k))*rdt/minval((/dzh(k),dx,dy/))**2)
        end do
        call MPI_ALLREDUCE(peclettotl,peclettot,1,MY_REAL,MPI_MAX,comm3d,mpierr)
        if ( pecletold>0) then
          dt = min(timee,dt_lim,idtmax,floor(rdt/tres*courant/courtotmax,longint),floor(rdt/tres*peclet/peclettot,longint))
          if (abs(courtotmax-courold)/courold<0.1 .and. (abs(peclettot-pecletold)/pecletold<0.1)) then
            spinup = .false.
          end if
        end if
        rdt = dble(dt)*tres
        dt_lim = timeleft
        timee   = timee  + dt
        rtimee  = dble(timee)*tres
        timeleft=timeleft-dt
        ntimee  = ntimee + 1
        ntrun   = ntrun  + 1
      else
        dt = 2 * dt
        if (dt >= idtmax) then
          dt = idtmax
          spinup = .false.
        end if
        rdt = dble(dt)*tres
      end if
    ! Normal time loop
    else
      if (ladaptive) then
        peclettotl = 1e-5
        do k=1,kmax
          courtotl(k)=maxval((um(2:i1,2:j1,k)*rdt/dx)*(um(2:i1,2:j1,k)*rdt/dx)+(vm(2:i1,2:j1,k)*rdt/dy)*&
          (vm(2:i1,2:j1,k)*rdt/dy)+(wm(2:i1,2:j1,k)*rdt/dzh(k))*(wm(2:i1,2:j1,k)*rdt/dzh(k)))
        end do
        call MPI_ALLREDUCE(courtotl,courtot,kmax,MY_REAL,MPI_MAX,comm3d,mpierr)
        courtotmax=0.0
        do k=1,kmax
            courtotmax=max(courtotmax,sqrt(courtot(k)))
        enddo
        do k=1,kmax
          peclettotl=max(peclettotl,maxval(ekm(2:i1,2:j1,k))*rdt/minval((/dzh(k),dx,dy/))**2)
        end do
        call MPI_ALLREDUCE(peclettotl,peclettot,1,MY_REAL,MPI_MAX,comm3d,mpierr)
        dt = min(timee,dt_lim,idtmax,floor(rdt/tres*courant/courtotmax,longint),floor(rdt/tres*peclet/peclettot,longint))
        rdt = dble(dt)*tres
        timeleft=timeleft-dt
        dt_lim = timeleft
        timee   = timee  + dt
        rtimee  = dble(timee)*tres
        ntimee  = ntimee + 1
        ntrun   = ntrun  + 1
      else
        dt = idtmax
        rdt = dtmax
        ntimee  = ntimee + 1
        ntrun   = ntrun  + 1
        timee   = timee  + dt !ntimee*dtmax
        rtimee  = dble(timee)*tres
        timeleft=timeleft-dt
      end if
    end if
  end if

  deallocate(courtotl,courtot)

end subroutine tstep_update


!> Time integration is done by a third order Runge-Kutta scheme.
!!
!! \latexonly
!! With $f^n(\phi^n)$ the right-hand side of the appropriate equation for variable
!! $\phi=\{\fav{u},\fav{v},\fav{w},e^{\smfrac{1}{2}},\fav{\varphi}\}$, $\phi^{n+1}$
!! at $t+\Delta t$ is calculated in three steps:
!! \begin{eqnarray}
!! \phi^{*} &=&\phi^n + \frac{\Delta t}{3}f^n(\phi^n)\nonumber\\\\
!! \phi^{**} &=&\phi^{n} + \frac{\Delta t}{2}f^{*}(\phi^{*})\nonumber\\\\
!! \phi^{n+1} &=&\phi^{n} + \Delta t f^{**}(\phi^{**}),
!! \end{eqnarray}
!! with the asterisks denoting intermediate time steps.
!! \endlatexonly
!! \see Wicker and Skamarock, 2002
subroutine tstep_integrate


  use modglobal, only : i1,j1,kmax,nsv,rdt,rk3step,e12min
  use modfields, only : u0,um,up,v0,vm,vp,w0,wm,wp,wp_store,&
                        thl0,thlm,thlp,qt0,qtm,qtp,&
                        e120,e12m,e12p,sv0,svm,svp,ql0, qlm
  use modmicrodata, only: inr, iqr      

  implicit none

  integer i,j,k,n
  real rk3coef

  rk3coef = rdt / (4. - dble(rk3step))
  wp_store = wp

  do k=1,kmax
  do j=2,j1
  do i=2,i1

     u0(i,j,k)   = um(i,j,k)   + rk3coef * up(i,j,k)
     v0(i,j,k)   = vm(i,j,k)   + rk3coef * vp(i,j,k)
     w0(i,j,k)   = wm(i,j,k)   + rk3coef * wp(i,j,k)
     thl0(i,j,k) = thlm(i,j,k) + rk3coef * thlp(i,j,k)
     qt0(i,j,k)  = qtm(i,j,k)  + rk3coef * qtp(i,j,k)
     e120(i,j,k) = e12m(i,j,k) + rk3coef * e12p(i,j,k)

     e120(i,j,k) = max(e12min,e120(i,j,k))
     e12m(i,j,k) = max(e12min,e12m(i,j,k))


     ! To ensure mass conservation don't clip aerosol tracers. (MdB)           
     do n=1,nsv
        if (n == iqr .or. n == inr) then  
           if (svm(i,j,k,n) + rk3coef * svp(i,j,k,n) > 0.) then
              sv0(i,j,k,n) = svm(i,j,k,n) + rk3coef * svp(i,j,k,n)
           else
              sv0(i,j,k,n) = 0.           
           endif
        else
           sv0(i,j,k,n) = svm(i,j,k,n) + rk3coef * svp(i,j,k,n)
        endif    
     end do

  end do
  end do
  end do

  up=0.
  vp=0.
  wp=0.
  thlp=0.
  qtp=0.
  svp=0.
  e12p=0.

  if (rk3step == 3) then
    um   = u0
    vm   = v0
    wm   = w0
    thlm = thl0
    qtm  = qt0
    e12m = e120
    svm  = sv0
    qlm  = ql0    
  end if

end subroutine tstep_integrate

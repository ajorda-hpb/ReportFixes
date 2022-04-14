SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[SR_ShipmentNotReceived] 
--Declare
	@StartDate datetime   --= '1/01/15'
	,@EndDate datetime   --= '7/31/15'
	,@FilterType char(20) --= 'All Locations' -- Store, District, Region, RDC, State
	,@DynFilter char(20) --= 'All Locations'
	,@VendorID varchar(10) --= 'IDCROWNPOI' --'All' --'CDC', 'IDCROWNPOI','IDCROWNB&C', etc
AS

	If OBJECT_ID('tempDB..#LOCS') IS NOT NULL drop table #LOCS
	If OBJECT_ID('tempDB..#ShipmentReceived') IS NOT NULL drop table #ShipmentReceived
	If OBJECT_ID('tempDB..#ShipmentReceivedCDC') IS NOT NULL drop table #ShipmentReceivedCDC
	If OBJECT_ID('tempDB..#ShipmentReceivedDrop') IS NOT NULL drop table #ShipmentReceivedDrop
	If OBJECT_ID('tempDB..#ShipmentAll') IS NOT NULL drop table #ShipmentAll
	If OBJECT_ID('tempDB..#ShipmentAllCDC') IS NOT NULL drop table #ShipmentAllCDC
	If OBJECT_ID('tempDB..#ShipmentAllDrop') IS NOT NULL drop table #ShipmentAllDrop
	If OBJECT_ID('tempDB..#Vendor') IS NOT NULL drop table #Vendor

SET @EndDate=(DATEADD(d, 1, @EndDate))

--Location logic	
	CREATE TABLE #LOCS(LocationNo CHAR(5), LocationName CHAR(30))
IF @FilterType = 'All Locations'
	BEGIN
	INSERT  #LOCS
	SELECT 
		LocationNo, [Name]
		FROM reportsdata..Locations 
		WHERE LocationType = 'S'
			AND RetailStore = 'Y'
	ORDER BY LocationNo
	END
IF @FilterType = 'Store'
	BEGIN
	INSERT  #LOCS
	SELECT 
	LocationNo, [Name]
		FROM ReportsData..Locations WHERE LocationNo = @DynFilter AND RetailStore = 'Y'
	END
IF @FilterType = 'District'
	BEGIN
	INSERT  #LOCS
	SELECT 
	LocationNo, [Name]
		FROM ReportsData..Locations WHERE DistrictCode = @DynFilter AND RetailStore = 'Y'
	END
IF @FilterType = 'Region'
	BEGIN
	INSERT  #LOCS
	SELECT 
	LocationNo, [Name]
		FROM  ReportsData..ReportLocations WHERE Region = @DynFilter AND Retail = 'Y'
	END
IF @FilterType = 'RDC'
BEGIN
INSERT  #LOCS
	SELECT 
	LocationNo, [Name]
	FROM reportsdata..Locations 
	WHERE
		 LocationNo NOT IN ('00451','00710','00999')
		AND RDCLocationNo = @DynFilter  AND RetailStore = 'Y'
	END
IF @FilterType = 'State'
	BEGIN
	INSERT  #LOCS
	SELECT 
		LocationNo, [Name]
		FROM reportsdata..Locations 
		WHERE LocationType = 'S'
			AND RetailStore = 'Y'
			AND StateCode = @DynFilter
	ORDER BY LocationNo
	END

IF @VendorID = 'All'  
     BEGIN
  	  --Get all (non-supply) shipments during time period
	  SELECT distinct sh.ShipmentNo, sh.ShipmentType, l.LocationNo +' - '+ l.LocationName as Location, sh.ToLocationNo, 
	  convert(varchar(10),sh.DateTransferred,101) as ShipmentDate
	  into #ShipmentAll
	  FROM [rILS_Data].[dbo].[ShipmentHeader] sh
      join [rILS_Data].[dbo].[ShipmentDetail] sd on sh.ShipmentNo = sd.ShipmentNo and sh.ShipmentType = sd.ShipmentType
	  join #LOCS l on sh.ToLocationNo = l.LocationNo
	  where sh.DateTransferred >= @StartDate 
	  and sh.DateTransferred < @EndDate
	  and sh.ShipmentType in ('W','R') --Warehouse / WMS and Drop Shipment
      and sd.Company <> 'SUP' --Exclude/ignore supply shipments (never received)
	  
	  --get everything that has be received/partially first
	  SELECT a.ShipmentNo, a.ShipmentType, SUM(rd.qty) as qty
	  into #ShipmentReceived
	  FROM #ShipmentAll a
	  join [ReportsData].[dbo].[SR_Header] rh on a.ShipmentNo = rh.ShipmentNo and a.ShipmentType = rh.ShipmentType 
	  join [ReportsData].[dbo].[SR_Detail] rd on  rh.BatchID = rd.BatchID 
	  group by a.ShipmentNo, a.ShipmentType 
	  having SUM(rd.qty) > 0
	  order by a.ShipmentNo, a.ShipmentType 
	    
	  --Now by process of elmination what has not been received
	  SELECT 
			distinct isnull(v.VendorID, 'No Shipping Detail') +' - '+ isnull(v.Name, '')  AS Vendor
			,a.Location
			,a.ShipmentDate
			,a.ShipmentNo as ShipmentNumber
			,a.ShipmentType
	  INTO #Vendor
	  FROM #ShipmentAll a
	  LEFT JOIN [rILS_Data].[dbo].[Shipment_Detail] sd on a.ShipmentNo = sd.ShipmentNo and a.ShipmentType = sd.ShipmentType and sd.ShipmentType = 'R' --Drop Shipment
	  LEFT JOIN [ReportsData].dbo.VendorMaster v on sd.VendorId = v.VendorID and sd.ShipmentType = 'R' --Drop Shipment
	  LEFT JOIN #ShipmentReceived sr on a.ShipmentNo = sr.ShipmentNo and a.ShipmentType = sr.ShipmentType 
	  where sr.ShipmentNo is null --not in received /partially received shipments
	  order by a.Location, a.ShipmentDate ,a.ShipmentNo, a.ShipmentType 
	  
	  	  --Had to create tempory table to differentiate between Shipment Types	  
	  Select Location
			,ShipmentDate
			,ShipmentNumber
			,ShipmentType
			,Case ShipmentType
				When 'W' then 'CDC' --Warehouse / WMS
				When 'R' then Vendor --Drop Shipment
			  END	 as Vendor	
	  FROM #Vendor	
	END

ELSE IF @VendorID = 'CDC'
    --CDC ONLY
	BEGIN
       --Get all (non-supply) shipments during time period for CDC 
	  SELECT distinct sh.ShipmentNo, sh.ShipmentType, l.LocationNo +' - '+ l.LocationName as Location, sh.ToLocationNo, 
	  convert(varchar(10),sh.DateTransferred,101) as ShipmentDate
	  into #ShipmentAllCDC
	  FROM [rILS_Data].[dbo].[ShipmentHeader] sh
      join [rILS_Data].[dbo].[ShipmentDetail] sd on sh.ShipmentNo = sd.ShipmentNo and sh.ShipmentType = sd.ShipmentType
	  join #LOCS l on sh.ToLocationNo = l.LocationNo
	  where sh.DateTransferred >= @StartDate 
	  and sh.DateTransferred < @EndDate
	  and sh.ShipmentType in ('W') --Warehouse / WMS / CDC
      and sd.Company <> 'SUP' --Exclude/ignore supply shipments (never received)
	  
	  --get everything that has be received/partially first
	  SELECT a.ShipmentNo, a.ShipmentType ,SUM(rd.qty) as qty
	  into #ShipmentReceivedCDC
	  FROM #ShipmentAllCDC a
	  join [ReportsData].[dbo].[SR_Header] rh on a.ShipmentNo = rh.ShipmentNo and a.ShipmentType = rh.ShipmentType 
	  join [ReportsData].[dbo].[SR_Detail] rd on  rh.BatchID = rd.BatchID 
	  group by a.ShipmentNo, a.ShipmentType 
	  having SUM(rd.qty) > 0
	  order by a.ShipmentNo, a.ShipmentType  
	    
	  --Now by process of elmination what has not been received
	  SELECT a.Location
			,a.ShipmentDate
			,a.ShipmentNo as ShipmentNumber
			,a.ShipmentType
			,'CDC' as Vendor	
	  FROM #ShipmentAllCDC a
	  LEFT JOIN #ShipmentReceivedCDC sr on a.ShipmentNo = sr.ShipmentNo and a.ShipmentType = sr.ShipmentType 

	  where sr.ShipmentNo is null --not in received /partially received shipments
	  order by a.Location, a.ShipmentDate ,a.ShipmentNo, a.ShipmentType 
	END	  
ELSE
    BEGIN	
	  --Get everything for Vendor	
	  SELECT distinct(sh.ShipmentNo) as ShipmentNo, sh.ShipmentType, l.LocationNo +' - '+ l.LocationName as Location, sh.ToLocationNo, 
	  convert(varchar(10),sh.DateTransferred,101) as ShipmentDate, sd.VendorID 
	  into #ShipmentAllDrop
	  
	  FROM [rILS_Data].[dbo].[ShipmentHeader] sh
	  join [rILS_Data].[dbo].[ShipmentDetail] sd on sh.ShipmentNo = sd.ShipmentNo and sh.ShipmentType = sd.ShipmentType
	  join #LOCS l on sh.ToLocationNo = l.LocationNo
	  where sh.DateTransferred >= @StartDate 
	  and sh.DateTransferred < @EndDate
	  and sh.ShipmentType in ('R')  --Drop Shipment
	  and sd.VendorID = @VendorID                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	
	  --get everything that has be received/partially first	
	  SELECT a.ShipmentNo, a.ShipmentType, SUM(rd.qty) as qty
	  into #ShipmentReceivedDrop
	  FROM #ShipmentAllDrop a
	  join [ReportsData].[dbo].[SR_Header] rh on a.ShipmentNo = rh.ShipmentNo and a.ShipmentType = rh.ShipmentType 
	  join [ReportsData].[dbo].[SR_Detail] rd on  rh.BatchID = rd.BatchID 
	  where a.VendorID = @VendorID                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       
	  group by a.ShipmentNo,a.ShipmentType
	  having SUM(rd.qty) > 0
	  order by a.ShipmentNo, a.ShipmentType 
	  
 --Now by process of elmination what has not been received
	  SELECT 
			distinct isnull(v.VendorID, 'No Shipping Detail') +' - '+ isnull(v.Name, '')  AS Vendor
			,a.Location
			,a.ShipmentDate
			,a.ShipmentNo as ShipmentNumber
			,a.ShipmentType
	  FROM #ShipmentAllDrop a
	  LEFT JOIN #ShipmentReceivedDrop sr on a.ShipmentNo = sr.ShipmentNo and a.ShipmentType = sr.ShipmentType
	  LEFT JOIN [rILS_Data].[dbo].[Shipment_Detail] sd on a.ShipmentNo = sd.ShipmentNo and a.ShipmentType = sd.ShipmentType and sd.ShipmentType = 'R' --Drop Shipment
	  LEFT JOIN [ReportsData].dbo.VendorMaster v on sd.VendorId = v.VendorID and sd.ShipmentType = 'R' --Drop Shipment
 
	  where sr.ShipmentNo is null --not in received /partially received shipments
	  order by a.Location, a.ShipmentDate, a.ShipmentNo, a.ShipmentType, isnull(v.VendorID, 'No Shipping Detail') +' - '+ isnull(v.Name, '') 
	  
	END

	If OBJECT_ID('tempDB..#LOCS') IS NOT NULL drop table #LOCS
	If OBJECT_ID('tempDB..#ShipmentReceived') IS NOT NULL drop table #ShipmentReceived
	If OBJECT_ID('tempDB..#ShipmentReceivedCDC') IS NOT NULL drop table #ShipmentReceivedCDC
	If OBJECT_ID('tempDB..#ShipmentReceivedDrop') IS NOT NULL drop table #ShipmentReceivedDrop
	If OBJECT_ID('tempDB..#ShipmentAll') IS NOT NULL drop table #ShipmentAll
	If OBJECT_ID('tempDB..#ShipmentAllCDC') IS NOT NULL drop table #ShipmentAllCDC
	If OBJECT_ID('tempDB..#ShipmentAllDrop') IS NOT NULL drop table #ShipmentAllDrop
	If OBJECT_ID('tempDB..#Vendor') IS NOT NULL drop table #Vendor
GO

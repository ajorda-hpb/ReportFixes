-- set ANSI_NULLS on
-- go
-- set QUOTED_IDENTIFIER on
-- go
-- -- =============================================
-- -- Author:		<Joey B.>
-- -- Create date: <3/12/14>
-- -- Description:	<Used to roll-up TTB Profit by Title information for WMS report...>
-- -- =============================================
-- create procedure [dbo].[RU_TTB_ProfitByTitle]

-- as
-- begin
-- 	-- SET NOCOUNT ON added to prevent extra result sets from
-- 	-- interfering with SELECT statements.
-- 	set NOCOUNT on;

	drop table if exists #curreorderables
	select distinct
		pm.Title
		,right(pm.ItemCode,7)[ItemCode]
		,isnull(pd.ReportitemCode, pd.itemcode)[ReportitemCode]
		,case when isnull(ltrim(rtrim(pm.ISBN)),'')<>'' then pm.ISBN else pd.UPC end[ISBN]
		,pm.Cost
		,pm.Price
		,pm.MfgSuggestedPrice[MSRP]
		,pm.SectionCode
		,pm.VendorID
		-- ,(select min(PONumber)
		-- 	from ReportsData..OrderDetail
		-- 	where ItemCode=pm.ItemCode)[OrgPO]
		,cast(''as varchar(15))[OrgPO]
		,cast(''as varchar(15))[OrgBuyer]
	into #curreorderables
	from ReportsData..ProductMaster pm 
		inner join ReportsData..ProductMasterDist pd on pm.ItemCode=pd.ItemCode
	where pm.UserChar15='TTB' and pm.Reorderable='Y'


	----get UPC/ISBN items....
	drop table if exists #upcItems
	select
		pm.ItemCode
		,pmd.ReportItemCode
	into #upcItems
	from ReportsData..ProductMaster pm with (nolock) 
		inner join ReportsData..ProductMasterDist pmd with (nolock) on pm.ItemCode=pmd.ItemCode
	where pm.UserChar15='TTB' 
		and pm.ItemCode in(
			select distinct right('00000000000000000000' + replace(ItemAlias,'UPC',''),20)
			from ReportsData..ProductMaster
			where ItemAlias like 'UPC%')


	--***adding in all items that are not reorderable but have the reportitemcode of any of the current reorderables
	drop table if exists #items
	select
		Title
		,ItemCode
		,ReportItemCode
		,ISBN
		,Cost
		,Price
		,MSRP
		,SectionCode
		,VendorID
		,OrgPO
		,OrgBuyer
	into #items
	from(	select
				r.Title
				,right(pm.ItemCode,7)[ItemCode]
				,isnull(pmd.ReportitemCode, pmd.itemcode)[ReportitemCode]
				,r.ISBN
				,r.Cost
				,r.Price
				,r.MSRP
				,r.SectionCode
				,r.VendorID
				,r.OrgPO
				,r.OrgBuyer
			from reportsdata..productmasterdist pmd with(nolock) 
				join reportsdata..productmaster pm with(nolock) on pm.itemcode = pmd.itemcode
				-- !!BAD JOIN. There can be >1 ItemCode with the same ReportItemCode ==> lines replicated at rate of 2^n.
				join #curreorderables r on r.reportitemcode = pmd.reportitemcode
			where pm.UserChar15='TTB' 
				and pmd.ItemCode not in (select ItemCode from #upcItems)
				and r.ReportItemCode in ('00000000000002201031')
		union
			select
				Title
				,ItemCode
				,ReportItemCode
				,ISBN
				,Cost
				,Price
				,MSRP
				,SectionCode
				,VendorID
				,OrgPO
				,OrgBuyer
			from #curreorderables) r


    select * from #curreorderables where ReportItemCode in ('00000000000002201031') --1604052','2001323')
    select * from #items where itemcode in ('2105098') --1604052','2001323')
       select * from Reports..RU_TTB_Profit_by_Title where itemcode in ('1604052','2001323')
	select ReportItemCode,count(*) from #curreorderables group by ReportItemCode having count(*) > 1

	----adding in UPC items excluded from previous step....
	insert into #items
	select
		pm.Title
		,right(pm.ItemCode,7)[ItemCode]
		,isnull(pmd.ReportitemCode, pmd.itemcode)[ReportitemCode]
		,case when isnull(ltrim(rtrim(pm.ISBN)),'')<>'' then pm.ISBN else pmd.UPC end[ISBN]
		,pm.Cost
		,pm.Price
		,pm.MfgSuggestedPrice[MSRP]
		,pm.SectionCode
		,pm.VendorID
		-- ,(select min(PONumber)
		-- 	from ReportsData..OrderDetail
		-- 	where ItemCode=pm.ItemCode)[OrgPO]
		,cast(''as varchar(15))[OrgPO]
		,cast(''as varchar(15))[OrgBuyer]
	from reportsdata..productmasterdist pmd with(nolock) 
		inner join reportsdata..productmaster pm with(nolock) on pm.itemcode = pmd.itemcode
		inner join #curreorderables r on r.reportitemcode = pmd.reportitemcode
	where pm.UserChar15='TTB' 
		and pmd.ItemCode in (select ItemCode from #upcItems)

--     select * from #items where itemcode in ('1604052','2001323')


	------flip any items back that have been reactivated under an older itemcode......
	update r 
	set r.ReportItemCode = right('00000000000000000000'
		+ (select top 1 ItemCode
			from #curreorderables
			where ReportItemCode=r.ReportItemCode
			order by ItemCode desc),20)
	from #items r
	where r.ReportItemCode in(
		select ReportItemCode
		from #curreorderables
		where right('00000000000000000000'+ItemCode,20)<>right('00000000000000000000'+ReportItemCode,20))

    select * from #items where itemcode in ('1604052','2001323')

	------get CDC out of stock items over past year and add in...
	insert into #items
	select
		distinct
		pm.Title
		,right(pm.ItemCode,7)[ItemCode]
		,isnull(pd.ReportitemCode, pd.itemcode)[ReportitemCode]
		,case when isnull(ltrim(rtrim(pm.ISBN)),'')<>'' then pm.ISBN else pd.UPC end[ISBN]
		,pm.Cost
		,pm.Price
		,pm.MfgSuggestedPrice[MSRP]
		,pm.SectionCode
		,pm.VendorID
		-- ,(select min(PONumber)
		-- 	from ReportsData..OrderDetail
		-- 	where ItemCode=pm.ItemCode)[OrgPO]
		,cast(''as varchar(15))[OrgPO]
		,cast(''as varchar(15))[OrgBuyer]
	from ReportsData..CDC_OOS_ItemLog il 
		inner join ReportsData..ProductMaster pm on right('00000000000000000000'+il.Item,20)=pm.ItemCode
		inner join ReportsData..ProductMasterDist pd on pm.ItemCode=pd.ItemCode
	where right(pm.ItemCode,7) not in (select ItemCode from #items)
	group by pm.Title
		,right(pm.ItemCode,7)
		,isnull(pd.ReportitemCode, pd.itemcode)
		,case when isnull(ltrim(rtrim(pm.ISBN)),'')<>'' then pm.ISBN else pd.UPC end
		,pm.Cost
		,pm.Price
		,pm.MfgSuggestedPrice
		,pm.SectionCode
		,pm.VendorID
		,pm.ItemCode
	having MAX(il.runtime)>DATEADD(year,-1,getdate())

	----update items with BuyerIDs.....................
	update i
	set OrgBuyer = h.BuyerID
	from #items i 
		inner join ReportsData..Orderheader h with(nolock) on i.OrgPO=h.PONumber


	----get receiving data.......
	drop table if exists #receiptsHold
	select
			i.ItemCode
			,MIN(rh.RECEIPT_DATE)[RcvdDate]
			,cast(sum(isnull(rd.TOTAL_QTY,0))as int)[RcvdQty]
			,cast(sum(rd.TOTAL_QTY)*max(i.Cost) as money)[RcvdAmt]
		into #receiptsHold
		from rILS_DATA..RECEIPT_HEADER rh 
			inner join rILS_DATA..RECEIPT_DETAIL rd on rh.RECEIPT_ID=rd.RECEIPT_ID
			inner join #items i on rd.ITEM=i.ItemCode
		group by i.ItemCode
	union
		select
			i.ItemCode
			,MIN(rh.RECEIPT_DATE)[RcvdDate]
			,cast(sum(isnull(rd.TOTAL_QTY,0))as int)[RcvdQty]
			,cast(sum(rd.TOTAL_QTY)*max(i.Cost) as money)[RcvdAmt]
		from rILS_DATA..AR_RECEIPT_HEADER rh 
			inner join rILS_DATA..AR_RECEIPT_DETAIL rd on rh.RECEIPT_ID=rd.RECEIPT_ID
			inner join #items i on rd.ITEM=i.ItemCode
		group by i.ItemCode
	order by i.ItemCode


	insert into #receiptsHold
	select
		i.ItemCode
		,MIN(h.receiptdate)[RcvdDate]
		,cast(sum(isnull(d.EXTDCOST/case when d.UNITCOST= 0 then 1 else d.UNITCOST end,0))as int)[RcvdQty]
		,cast(sum(isnull(d.EXTDCOST,0))as money)[RcvdAmt]
	from ReportsData..TB_POP30300 h 
		inner join ReportsData..TB_POP30310 d on h.POPRCTNM=d.POPRCTNM
		inner join #items i on d.ITEMNMBR=i.ItemCode
	where h.POPTYPE=1 
		and h.receiptdate < '6/30/2010'
	group by i.ItemCode
	order by i.ItemCode

-- select * from #receiptsHold where itemcode = '1604052'

	drop table if exists #receipts
	select
		r.ItemCode
		,MIN(r.RcvdDate)[RcvdDate]
		,SUM(r.RcvdQty)[RcvdQty]
		,SUM(r.RcvdAmt)[RcvdAmt]
	into #receipts
	from #receiptsHold r
	group by r.ItemCode


	----get Shipment data to Stores........
	drop table if exists #storeShip
	select
		i.ItemCode
		,CAST(sum(sd.Qty)as int)[HPBShipQty]
		,CAST(sum(sd.Qty)*i.cost as money)[HPBShipAmt]
	into #storeShip
	from ReportsData..ShipmentHeader sh 
		inner join ReportsData..ShipmentDetail sd on sh.TransferID=sd.TransferID
		inner join #items i on sd.ItemCode=right('00000000000000000000'+i.ItemCode,20)
	group by i.ItemCode,i.Cost
	order by i.ItemCode

-- select * from #storeShip where itemcode = '1604052'

	----get Retail sales data........
	drop table if exists #storeSales
	select
		distinct
		i.ItemCode
		,isnull(sum(case sih.isreturn when 'y' then - sih.quantity else sih.quantity end),0)[HPBSoldQty]
		,SUM(sih.ExtendedAmt)[HPBSoldAmt]
		,AVG(sih.ExtendedAmt)[HPBAvgSoldAmt]
		,sum(case when sih.unitprice > sih.registerprice and isreturn = 'n' then 1 else 0 end)[HPBmarkdowns]
	into #storeSales
	from rHPB_Historical..SalesItemHistory sih 
		inner join ReportsData..Locations l on sih.LocationID=l.LocationID
		inner join #items i on sih.ItemCode=right('00000000000000000000'+i.ItemCode,20)
	where sih.XactionType='S' 
		and l.retailstore = 'y' 
		and isnumeric(l.locationno) = 1 
		and l.status = 'A' 
		and CAST(l.locationno as int) between 1 and 200
	group by i.ItemCode
	order by i.ItemCode

-- select * from #storeSales where itemcode = '1604052'

	----get Wholesale sales data.......
	drop table if exists #wholeSalesCalc
	select distinct
			sopd.ITEMNMBR
			,sum(sopd.QTYTOINV)[TTBSoldQty]
			,sum(sopd.XTNDPRCE)[TTBSoldAmt]
			,case when sum(sopd.QTYTOINV)=0 then 0 else (sum(sopd.XTNDPRCE)/sum(sopd.QTYTOINV))end[TTBAvgSoldAmt]
		into #wholeSalesCalc
		from ReportsData..TB_SOP10100 soph 
			inner join ReportsData..TB_SOP10200 sopd on soph.SOPNUMBE=sopd.SOPNUMBE
			inner join #items i on sopd.ITEMNMBR=i.ItemCode
		where soph.SOPTYPE=3 
			and soph.CUSTNMBR not in ('SAMPLE','REPS') 
			and soph.DOCID='STD' 
			and soph.BCHSOURC !='Sales Void'
			and soph.CUSTNMBR not like 'MRDC%' 
			and soph.CUSTNMBR not like 'RDC%' 
			and soph.CUSTNMBR not like 'TTB%'
		group by sopd.ITEMNMBR
	union
		select distinct
			sopd.ITEMNMBR
			,sum(sopd.QTYTOINV)[TTBSoldQty]
			,sum(sopd.XTNDPRCE)[TTBSoldAmt]
			,case when sum(sopd.QTYTOINV)=0 then 0 else (sum(sopd.XTNDPRCE)/sum(sopd.QTYTOINV))end[TTBAvgSoldAmt]
		from ReportsData..TB_SOP30200 soph 
			inner join ReportsData..TB_SOP30300 sopd on soph.SOPNUMBE=sopd.SOPNUMBE
			inner join #items i on sopd.ITEMNMBR=i.ItemCode
		where soph.SOPTYPE=3 
			and soph.CUSTNMBR not in ('SAMPLE','REPS') 
			and soph.DOCID='STD' 
			and soph.BCHSOURC !='Sales Void'
			and soph.CUSTNMBR not like 'MRDC%' 
			and soph.CUSTNMBR not like 'RDC%' 
			and soph.CUSTNMBR not like 'TTB%'
		group by sopd.ITEMNMBR
	order by sopd.ITEMNMBR

-- select * from #wholeSalesCalc where ITEMNMBR = '1604052'

	----consolidate sales data......
	drop table if exists #wholeSales
	select
		c.ITEMNMBR
		,SUM(c.TTBSoldQty)[TTBSoldQty]
		,SUM(c.TTBSoldAmt)[TTBSoldAmt]
		,AVG(c.TTBAvgSoldAmt)[TTBAvgSoldAmt]
	into #wholeSales
	from #wholeSalesCalc c
	group by c.ITEMNMBR
	order by c.ITEMNMBR

-- select * from #wholeSales where ITEMNMBR = '1604052'

	--select * from #items where ItemCode in ('1503026','1604040') 
	--select * from #wholeSalesCalc where ITEMNMBR in ('1503026','1604040') 
	--select * from #wholeSales where ITEMNMBR in ('1503026','1604040') 



-- 	------clear table....
-- 	truncate table Reports..RU_TTB_Profit_by_Title

-- 	----------get the final results.......insert into RU_TTB_Profit_by_Title
-- 	insert into Reports..RU_TTB_Profit_by_Title
	select
		distinct
		i.ItemCode
		,i.Title
		,i.ISBN
		,i.SectionCode
		,i.VendorID
		,i.Cost
		,i.Price
		,i.MSRP
		,i.OrgBuyer
		,i.OrgPO
		,isnull(cast(cast(r.RcvdDate as date)as varchar(15)),'NA')[RcvdDate]
		,isnull(case when isnull(cast(r.RcvdDate as date),'')='' then w.AvailableQty + cast(ISNULL(ship.HPBShipQty,0)as int) + cast(isnull(ws.TTBSoldQty,0)as int)
			else isnull(r.RcvdQty,0) end,0) [RcvdQty]
		,isnull(case when isnull(cast(r.RcvdDate as date),'')='' then cast((isnull(w.AvailableQty,0)*i.Cost) + (cast(ISNULL(ship.HPBShipQty,0)as int)*i.Cost) + (cast(isnull(ws.TTBSoldQty,0)as int)*i.Cost) as money)
			else isnull(r.RcvdAmt,0) end,0) [RcvdAmt]
		,isnull(w.AvailableQty,0)[WMSAvailQty]
		,cast(isnull(ws.TTBSoldQty,0)as int)[NetTTBSoldQty]
		,cast(isnull(ws.TTBSoldAmt,0)as money)[TTBSoldAmt]
		,cast(isnull(ws.TTBAvgSoldAmt,0)as money)[TTBAvgSoldAmt]
		,case when cast(isnull(ws.TTBSoldQty,0)as int)=0 then 0 else cast(isnull(ws.TTBAvgSoldAmt,0)as money)-i.cost end [TTBAvgPrf]
		,case when cast(isnull(ws.TTBSoldQty,0)as int)=0 then 0 else i.price-cast(isnull(ws.TTBAvgSoldAmt,0)as money) end [TTBAvgDisc]
		,cast(case when cast(isnull(ws.TTBSoldQty,0)as int)=0 or i.price=0 then 0 else ((i.price-cast(isnull(ws.TTBAvgSoldAmt,0)as money))/i.Price)*100 end as varchar(10))+' %' [TTBAvgDiscPct]
		,cast(isnull(ss.HPBSoldQty,0)as int)[NetHPBSoldQty]
		,cast(isnull(ss.HPBmarkdowns,0)as int)[HPBMRKDQty]
		,cast(cast(case when cast(isnull(ss.HPBSoldQty,0)as int)=0 then 0 else (cast(isnull(ss.HPBmarkdowns,0)as numeric)/cast(isnull(ss.HPBSoldQty,0)as numeric))*100 end as decimal(8,4))as varchar(20))+' %'[HPBMRKDPct]
		,cast(isnull(ss.HPBSoldAmt,0)as money)[HPBSoldAmt]
		,cast(isnull(ss.HPBAvgSoldAmt,0)as money)[HPBAvgSoldAmt]
		,cast(ISNULL(ship.HPBShipQty,0)as int)[HPBShipQty]
		,cast(ISNULL(ship.HPBShipAmt,0)as money)[HPBShipAmt]
		,cast(isnull(ws.TTBSoldQty,0)+isnull(ss.HPBSoldQty,0)as int)[NetTotalSold]
		,cast(isnull(ws.TTBSoldAmt,0)+isnull(ss.HPBSoldAmt,0)as money)[TotalAmt]
		,isnull(case when isnull(cast(r.RcvdDate as date),'')='' then (isnull(ws.TTBSoldAmt,0)+isnull(ss.HPBSoldAmt,0))-cast((isnull(w.AvailableQty,0)*i.Cost) + (cast(ISNULL(ship.HPBShipQty,0)as int)*i.Cost) + (cast(isnull(ws.TTBSoldQty,0)as int)*i.Cost) as money)
			else cast((isnull(ws.TTBSoldAmt,0)+isnull(ss.HPBSoldAmt,0))-isnull(r.RcvdAmt,0) as money) end,0) [GrossProfit]
		,GETDATE()[UpdateDate]
	into #wtf
	from #items i 
		left join #receipts r on i.ItemCode=r.ItemCode
		left join #storeShip ship on i.ItemCode=ship.ItemCode
		left join #storeSales ss on i.ItemCode=ss.ItemCode
		left join #wholeSales ws on i.ItemCode=ws.ITEMNMBR
		left join rILS_DATA..WMSAvailableQty w on i.ItemCode=w.ITEM
	-- where i.itemCode = '2001323' --1604052'
	order by i.ItemCode,i.Title,i.SectionCode,i.Cost,i.Price


--    select * from Reports..RU_TTB_Profit_by_Title where ItemCode = '1604052'
	  select * from #wtf where ItemCode = '2105098' --1604052'

select ItemCode,count(*) from Reports..RU_TTB_Profit_by_Title group by ItemCode having count(*) > 1
select ItemCode,count(*) from #wtf group by ItemCode having count(*) > 1
select ReportItemCode,count(*) from #curreorderables group by ReportItemCode having count(*) > 1


-- 	------clean up tables......
-- 	drop table #items
-- 	drop table #receipts
-- 	drop table #receiptsHold
-- 	drop table #storeShip
-- 	drop table #storeSales
-- 	drop table #wholeSales
-- 	drop table #wholeSalesCalc
-- 	drop table #curreorderables
-- 	drop table #upcItems

-- end


-- go

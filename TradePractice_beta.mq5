//+------------------------------------------------------------------+
//|                                                TradePractice.mq5 |
//|                                                       basicactor |
//|                                    https://neverdone.hateblo.jp/ |
//+------------------------------------------------------------------+
#property copyright "basicactor"
#property link      "https://neverdone.hateblo.jp/"
#property version     "1.2"
#property description "簡易トレード練習プログラムです。"
#property description "直感的な操作で練習ができます。"
#property description "左右ボタン：バーの移動　"
#property description "上下ボタン：新規買い/売り"
#property description "Enterキー：決済"
#property description "※両建はできません。成行注文のみ可能です。クロス円またはドルストレートのみ対応しています。"

#import "user32.dll"
void keybd_event(uchar vk,uchar scan,uint flags,ulong extra_info);
#import 

#include <VirtualKeys.mqh>
#include <Arrays\ArrayDouble.mqh>

//--- 入力パラメータ
input datetime                InpDate=D'2019.01.01'; //練習開始日
input double                  InpMoney=50000; //資金（円）
input double                  InpLotSize=1; //一取引あたりのロット数（1 Lot = 1万通貨）
input double                  InpSpread=1.6; //スプレッド（例：1銭＝1pips）
input color                   InpBuyColor=clrRed; //買いポジションの色
input color                   InpSellColor=clrBlue;//売りポジションの色
input color                   InpVLineColor=clrLightSeaGreen;//右端縦線の色

double MONEY=InpMoney;
int CURR_BAR_INDEX=0; //一番右端のバー（現在ポジション）のインデックス
datetime CURR_POS_TIME=InpDate; //一番右端のバー（現在ポジション）の日時
double CURR_CLOSE_PRICE=0.0; //一番右端のバー（現在ポジション）の終値
int LOT_BUY_TOTAL=0;
int LOT_SELL_TOTAL=0;
int LOT_BUY_HISTORICAL_TOTAL=0; //決済によってリセットされないヒストリカルロット数
int LOT_SELL_HISTORICAL_TOTAL=0;//決済によってリセットされないヒストリカルロット数
int COUNT_CLOSED=0;
double ENTRY_CLOSE_PRICE=0.0;
double TOTAL_RETURN_BUY=0.0;
double TOTAL_RETURN_SELL=0.0;
string DISPLAY_TIME="";
int CURRENCY=10000;
double SPREAD=InpSpread;


bool hasPosition()       { return LOT_BUY_TOTAL >0 || LOT_SELL_TOTAL > 0;}
CArrayDouble *entryPriceArray;

//+------------------------------------------------------------------+
//| 水平線を作成する                                                     |
//+------------------------------------------------------------------+
bool EntryHLineCreate(string tradeAction)
 {
   const long            chart_ID=0;       // チャート識別子
   string                name="";          // 記号名
   const int             sub_window=0;     // サブウィンドウ番号
   double                price=ENTRY_CLOSE_PRICE; // アンカーポイントの価格
   color                 clr=clrNONE;
//--- エラー値をリセットする
  ResetLastError();
//--- 垂直線を作成する
  if(tradeAction=="buy")
  {
  name= "#"+IntegerToString(LOT_BUY_TOTAL)+"EntryPriceLine";
  clr=InpBuyColor;
  
  if(!ObjectCreate(chart_ID,name,OBJ_HLINE,0,0,price))
    {
    Print(__FUNCTION__,
          ": failed to create a vertical line! Error code = ",GetLastError());
    return(false);
    }
  }
  if(tradeAction=="sell")
  {
  name= "#"+IntegerToString(LOT_SELL_TOTAL)+"EntryPriceLine";
  clr=InpSellColor;
  
  if(!ObjectCreate(chart_ID,name,OBJ_HLINE,0,0,price))
    {
    Print(__FUNCTION__,
          ": failed to create a vertical line! Error code = ",GetLastError());
    return(false);
    }
  }       
//--- 線の色を設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_COLOR,clr);
//--- 線の表示スタイルを設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_STYLE,STYLE_DASH);
//--- 線の幅を設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_WIDTH,1);
//--- 前景（false）または背景（true）に表示
  ObjectSetInteger(chart_ID,name,OBJPROP_BACK,false);
//--- hide (true) or display (false) graphical object name in the object list
  ObjectSetInteger(chart_ID,name,OBJPROP_HIDDEN,false);
//--- 実行成功
  return(true);
 }



//+------------------------------------------------------------------+
//| 垂直線を作成する                                                     |
//+------------------------------------------------------------------+
bool VLineCreate(datetime time)
 {
 const long           chart_ID=0;       // チャート識別子
 const string          name="AnchorVLine";     // 線の名称
 const int             sub_window=0;     // サブウィンドウ番号
 color                 clr=clrNONE;       // 線の色
 const ENUM_LINE_STYLE style=STYLE_SOLID; // 線のスタイル
 const int             width=3;           // 線の幅
 const bool            back=true;       // 背景で表示する
 
//--- エラー値をリセットする
  ResetLastError();
//--- 垂直線を作成する
  clr=InpVLineColor;
  if(!ObjectCreate(chart_ID,name,OBJ_VLINE,sub_window,time,0))
    {
    Print(__FUNCTION__,
          ": failed to create a vertical line! Error code = ",GetLastError());
    return(false);
    }
//--- 線の色を設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_COLOR,clr);
//--- 線の表示スタイルを設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_STYLE,style);
//--- 線の幅を設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_WIDTH,width);
//--- 前景（false）または背景（true）に表示
  ObjectSetInteger(chart_ID,name,OBJPROP_BACK,back);
//--- 実行成功
  return(true);
 }
 
//+------------------------------------------------------------------+
//| 垂直線を移動する                                                    |
//+------------------------------------------------------------------+
bool VLineMove(datetime time=0)       // 線の移動先の時間
 {
//--- 時間が設定されていない場合、最後のバーに移動する
  if(!time)
     time=CURR_POS_TIME;
//--- エラー値をリセットする
  ResetLastError();
//--- 垂直線を移動する
  if(!ObjectMove(0,"AnchorVLine",0,time,0))
    {
    Print(__FUNCTION__,
          ": failed to move the vertical line! Error code = ",GetLastError());
    return(false);
    }
//--- 実行成功
  return(true);
 }
 
//+------------------------------------------------------------------+
//| 水平線を削除する                                                     |
//+------------------------------------------------------------------+
bool HLineDelete(const long   chart_ID=0,   // チャート識別子
                const string name="EntryPriceLine") // 線の名称
 {
//--- エラー値をリセットする
  ResetLastError();
//--- 垂直線を削除する

int totalNumOfOrders = (LOT_BUY_TOTAL + LOT_SELL_TOTAL); 

for(int i=1;i<totalNumOfOrders+1;i++)// reason of +1 is that lot_total starts by 1
{
  string EntryPriceLineWithNum = "#"+IntegerToString(i)+name;
  if(!ObjectDelete(chart_ID,EntryPriceLineWithNum))// delete all Hlines of orders
    {
    Print(__FUNCTION__,
          ": failed to delete the vertical line! Error code = ",GetLastError());
    return(false);
    }
}
//--- 実行成功
  return(true);
 }
 
 
//+------------------------------------------------------------------+
//| 垂直線を削除する                                                     |
//+------------------------------------------------------------------+
bool VLineDelete(const long   chart_ID=0,   // チャート識別子
                const string name="AnchorVLine") // 線の名称
 {
//--- エラー値をリセットする
  ResetLastError();
//--- 垂直線を削除する
  if(!ObjectDelete(chart_ID,name))
    {
    Print(__FUNCTION__,
          ": failed to delete the vertical line! Error code = ",GetLastError());
    return(false);
    }
//--- 実行成功
  return(true);
 }

//+------------------------------------------------------------------+
//| 終値とトータルリターンを表示する                                         |
//+------------------------------------------------------------------+
void showPriceAndDayReturn(string nextOrBefore)
{    
    if(nextOrBefore=="next")CURR_BAR_INDEX -= 1;  
    if(nextOrBefore=="before")CURR_BAR_INDEX += 1;  
    CURR_POS_TIME=iTime(_Symbol,_Period,CURR_BAR_INDEX);
    VLineMove(CURR_POS_TIME); //VLineMoveはChartNavigateの前で呼ばれないと正しく動作しない
    
    CURR_CLOSE_PRICE = iClose(_Symbol,_Period,CURR_BAR_INDEX);
    
    DISPLAY_TIME=TimeToString(CURR_POS_TIME);
       
    
    if(LOT_BUY_TOTAL>0)
    {
      TOTAL_RETURN_BUY = calcTotalReturn("buy"); 
      Comment(StringFormat("Date: %s\nClose Price: %lf\nLot: %d buy\nSpread: %s(pips)\nReturn: %s Yen\nMoney: %s Yen",
       DISPLAY_TIME,
       CURR_CLOSE_PRICE,
       LOT_BUY_TOTAL,
       DoubleToString(InpSpread,1),
       DoubleToString(TOTAL_RETURN_BUY,0),
       DoubleToString(MONEY,0)));
    }
    else if(LOT_SELL_TOTAL>0)
    {
      TOTAL_RETURN_SELL = calcTotalReturn("sell");
      Comment(StringFormat("Date: %s\nClose Price: %lf\nLot: %d sell\nSpread: %s(pips)\nReturn: %s Yen\nMoney: %s Yen",
       DISPLAY_TIME,
       CURR_CLOSE_PRICE,
       LOT_SELL_TOTAL,
       DoubleToString(InpSpread,1),
       DoubleToString(TOTAL_RETURN_SELL,0),
       DoubleToString(MONEY,0)));
    }
    else // has no position
    {
      Comment(StringFormat("Date: %s\nClose Price: %lf\nMoney: %s Yen",
       DISPLAY_TIME,
       CURR_CLOSE_PRICE,
       DoubleToString(MONEY,0)));
    }
}
//+------------------------------------------------------------------+
//| トータルリターンを計算する                                               |
//+------------------------------------------------------------------+
double calcTotalReturn(string position)
{
   double totalReturn=0.0;
   if(entryPriceArray.Total() == 0) return totalReturn;

   
   for(int i=0; i<entryPriceArray.Total(); i++)
   {
      if(position == "buy")
      {
         totalReturn += (CURR_CLOSE_PRICE - entryPriceArray.At(i)- SPREAD)*InpLotSize*CURRENCY;
      }
      else if(position == "sell")
      {
         totalReturn += (entryPriceArray.At(i) - CURR_CLOSE_PRICE - SPREAD)*InpLotSize*CURRENCY;
      //printf("entryPriceArrayFor: %lf, totalReturn: %lf",entryPriceArray.At(i),totalReturn);
      }
   }
   
   //if(position == "sell") return -totalReturn;
   return totalReturn;
}
//+------------------------------------------------------------------+
//| 買い売りサインを作成する                                                  |
//+------------------------------------------------------------------+
bool EntryArrowCreate(string tradeAction)
 {
   const long            chart_ID=0;       // チャート識別子
   string                name="";          // 記号名
   const int             sub_window=0;     // サブウィンドウ番号
   datetime              time=CURR_POS_TIME;   // アンカーポイントの時刻
   double                price=ENTRY_CLOSE_PRICE; // アンカーポイントの価格
   color                 clr=clrNONE;      // 記号の色
   const ENUM_LINE_STYLE style=STYLE_SOLID; // 表示時の線のスタイル
   const int             width=2;           // 表示時の線のサイズ
   const bool            back=false;       // 背景で表示する
   const bool            selection=false;   // 強調表示して移動
   const bool            hidden=false;       // オブジェクトリストに隠す
   const long            z_order=0;         // マウスクリックの優先順位

//--- エラー値をリセットする
  ResetLastError();
//--- 記号を作成する
if(tradeAction == "buy")
{
   name= "#"+IntegerToString(LOT_BUY_HISTORICAL_TOTAL)+"ArrowBuy";
   clr=InpBuyColor;
   
   if(!ObjectCreate(chart_ID,name,OBJ_ARROW_BUY,sub_window,time,price))
   {
    Print(__FUNCTION__,
          ": failed to create \"Buy\" sign! Error code = ",GetLastError());
    return(false);
   }
} 
else if(tradeAction == "sell")
{
   name= "#"+IntegerToString(LOT_SELL_HISTORICAL_TOTAL)+"ArrowSell";
   clr=InpSellColor;
    
   
   if(!ObjectCreate(chart_ID,name,OBJ_ARROW_SELL,sub_window,time,price))
   {
    Print(__FUNCTION__,
          ": failed to create \"SELL\" sign! Error code = ",GetLastError());
    return(false);
   } 
}


//--- 記号の色を設定
  ObjectSetInteger(chart_ID,name,OBJPROP_COLOR,clr);
//--- 表示時の線のスタイルを設定
  ObjectSetInteger(chart_ID,name,OBJPROP_STYLE,style);
//--- 表示時の線のサイズを設定
  ObjectSetInteger(chart_ID,name,OBJPROP_WIDTH,width);
//--- 前景（false）または背景（true）に表示
  ObjectSetInteger(chart_ID,name,OBJPROP_BACK,back);
//--- オブジェクトリストのグラフィックオブジェクトを非表示（true）か表示（false）にする
  ObjectSetInteger(chart_ID,name,OBJPROP_HIDDEN,hidden);
//--- チャートのマウスクリックのイベントを受信するための優先順位を設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_ZORDER,z_order);
//--- 実行成功
  return(true);
 }
//+------------------------------------------------------------------+
//| 買い・売り・決済サインを削除する                                                  |
//+------------------------------------------------------------------+
bool TradeRecordOBJDelete()
 {

   const long   chart_ID=0;       // チャート識別子
   const int    sub_window=0;
   const string nameArrowBuy="ArrowBuy"; // 買いサイン名 
   const string nameArrowSell="ArrowSell"; // 売りサイン名 
   const string nameClosedSign="ClosedSign";// 決済サイン名
 
//--- エラー値をリセットする
  ResetLastError();

int totalArrowBuyObjects=ObjectsTotal(chart_ID,sub_window,OBJ_ARROW_BUY);
int totalArrowSellObjects=ObjectsTotal(chart_ID,sub_window,OBJ_ARROW_SELL);
int totalArrowTextObjects=ObjectsTotal(chart_ID,sub_window,OBJ_TEXT);

//--- 買いサインを削除する
for(int i=1;i<totalArrowBuyObjects+1;i++)// reason of +1 is that lot_total starts by 1
{
  if(!ObjectDelete(chart_ID,"#"+IntegerToString(i)+nameArrowBuy))// delete all Hlines of orders
    {
    Print(__FUNCTION__,
          ": failed to delete the vertical line! Error code = ",GetLastError());
    return(false);
    }
}

//--- 売りサインを削除する
for(int i=1;i<totalArrowSellObjects+1;i++)// reason of +1 is that lot_total starts by 1
{
  if(!ObjectDelete(chart_ID,"#"+IntegerToString(i)+nameArrowSell))// delete all Hlines of orders
    {
    Print(__FUNCTION__,
          ": failed to delete the vertical line! Error code = ",GetLastError());
    return(false);
    }
}
    
//--- 決済サインを削除する
for(int i=1;i<totalArrowTextObjects+1;i++)// reason of +1 is that lot_total starts by 1
{
  if(!ObjectDelete(chart_ID,"#"+IntegerToString(i)+nameClosedSign))// delete all Hlines of orders
    {
    Print(__FUNCTION__,
          ": failed to delete the vertical line! Error code = ",GetLastError());
    return(false);
    }
}
    
//--- 実行成功
  return(true);
 }

//+------------------------------------------------------------------+
//| チェックサインを作成する                                                 |
//+------------------------------------------------------------------+
bool ClosedSignCreate(string tradeAction)
 {
   const long              chart_ID=0;           // チャート識別子
   string                  name="";              // 記号名
   const int               sub_window=0;         // サブウィンドウ番号
   datetime                time=CURR_POS_TIME;               // アンカーポイントの時刻
   double                  price=CURR_CLOSE_PRICE;             // アンカーポイントの価格
   const string            text="★";             // テキスト
   const string            font="Arial";             // フォント
   const int               font_size=10;             // フォントサイズ
   color                   clr=clrNONE;           // 記号の色
   const double            angle=0.0;               // テキストの傾斜
   const ENUM_ANCHOR_POINT anchor=ANCHOR_UPPER; // アンカーの種類
   const bool              back=false;           // 背景で表示する
   const bool              selection=true;       // 強調表示して移動
   const bool              hidden=false;         // オブジェクトリストに隠す
   const long              z_order=0;           // マウスクリックの優先順位
//--- エラー値をリセットする
  ResetLastError();
  
  name= "#"+IntegerToString(COUNT_CLOSED)+"ClosedSign";
  
  if(tradeAction=="closeBuyPosition") clr=InpBuyColor;
  if(tradeAction=="closeSellPosition") clr=InpSellColor;
  
//--- テキストオブジェクトを作成する
  if(!ObjectCreate(chart_ID,name,OBJ_TEXT,sub_window,time,price))
    {
    Print(__FUNCTION__,
          ": failed to create \"Text\" object! Error code = ",GetLastError());
    return(false);
    }
//--- テキストを設定する
  ObjectSetString(chart_ID,name,OBJPROP_TEXT,text);
//--- テキストフォントを設定する
  ObjectSetString(chart_ID,name,OBJPROP_FONT,font);
//--- フォントサイズを設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_FONTSIZE,font_size);
//--- テキストの傾斜を設定する
  ObjectSetDouble(chart_ID,name,OBJPROP_ANGLE,angle);
//--- アンカーの種類を設定
  ObjectSetInteger(chart_ID,name,OBJPROP_ANCHOR,anchor);
//--- 色を設定
  ObjectSetInteger(chart_ID,name,OBJPROP_COLOR,clr);
//--- 前景（false）または背景（true）に表示
  ObjectSetInteger(chart_ID,name,OBJPROP_BACK,back);
//--- オブジェクトリストのグラフィックオブジェクトを非表示（true）か表示（false）にする
  ObjectSetInteger(chart_ID,name,OBJPROP_HIDDEN,hidden);
//--- チャートのマウスクリックのイベントを受信するための優先順位を設定する
  ObjectSetInteger(chart_ID,name,OBJPROP_ZORDER,z_order);
//--- 実行成功
  return(true);
 }

//+------------------------------------------------------------------+----------------------------------+
//| エキスパート初期化関数                                                                                  |
//+------------------------------------------------------------------+----------------------------------+
int OnInit()
 {
   //profit計算用
   if(StringSubstr(Symbol(),3,3)=="JPY")
   {
      CURRENCY=10000;
      SPREAD = InpSpread/100;
      //1pips = 0.01 Yen
   }
   else if(StringSubstr(Symbol(),3,3)=="USD")
   {
      CURRENCY=1000000;
      SPREAD = InpSpread/10000;
      //1pips = 0.0001 dollar
   }
   else
   {
     Comment("クロス円またはドルストレート以外の通貨取引ではご利用できません");
     Print("クロス円またはドルストレート以外の通貨取引ではご利用できません");
     OnDeinit(10);
   }
 
//--- オートスクロールを無効にする
  ChartSetInteger(ChartID(),CHART_AUTOSCROLL,false);
//--- チャートオブジェクト作成イベントの受信フラグを設定する
  ChartSetInteger(ChartID(),CHART_EVENT_OBJECT_CREATE,true);
//--- チャートオブジェクト削除イベントの受信フラグを設定する
  ChartSetInteger(ChartID(),CHART_EVENT_OBJECT_DELETE,true);
//--- ローソク足を描画する
  ChartSetInteger(ChartID(),CHART_MODE,CHART_CANDLES);
//--- マウスホイールスクロールメッセージの有効化
  ChartSetInteger(0,CHART_EVENT_MOUSE_WHEEL,1);   
  
  entryPriceArray=new CArrayDouble;
  if(entryPriceArray==NULL)
  {
    printf("CArrayDouble Object create error");
    return -1;
  }

  VLineCreate(InpDate);
  //--- 指定された時間に対応するバーがない場合、iBarShiftは一番近いバーのインデックスを返す
  CURR_BAR_INDEX=iBarShift(_Symbol,_Period,InpDate,false); //入力された日付のバーインデックスを返す
  CURR_POS_TIME=iTime(_Symbol,_Period,CURR_BAR_INDEX);
  DISPLAY_TIME=TimeToString(CURR_POS_TIME);
  
  printf("Program Started");
  ChartNavigate(0,CHART_END,-CURR_BAR_INDEX-1); //入力された日付がチャートの一番右に来るように移動 
  ChartRedraw();
  
  Comment(StringFormat("Date: %s\nReturn: 0 Yen\nMoney: %s Yen",DISPLAY_TIME,DoubleToString(InpMoney,0)));
//---
  return(INIT_SUCCEEDED);
 }
 
 //+------------------------------------------------------------------+
//| エキスパート削除時                                               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
 {
 //--- 初期化解除の理由コードを取得
  Print(__FUNCTION__," Deinitialization reason code = ",reason);
  
   HLineDelete();
   VLineDelete();
   TradeRecordOBJDelete();
   entryPriceArray.Shutdown();
   delete entryPriceArray;
   LOT_BUY_HISTORICAL_TOTAL=0;
   LOT_SELL_HISTORICAL_TOTAL=0;
 }

//+------------------------------------------------------------------+
//| チャートイベント開始                                                |
//+------------------------------------------------------------------+  
void OnChartEvent(const int id,
                    const long &lparam,
                    const double &dparam,
                    const string &sparam)
  { 
  //--- キーの押下
  if(id==CHARTEVENT_KEYDOWN)
    {  
      if(lparam == VK_RIGHT)//VK_RIGHT is written in VirtualKeys.mph
      {
         showPriceAndDayReturn("next");
         Sleep(10); // 時々４つ分移動してしまうため
         ChartNavigate(0,CHART_CURRENT_POS,-3); //CHART_CURRENT_POSは現在表示されているチャートの右端のバ         
         if(ObjectFind(0,"AnchorVLine")!=1) VLineCreate(CURR_POS_TIME); //VLineが消えた場合の対応策    
      }
      
      if(lparam == VK_LEFT)//VK_LEFT is written in VirtualKeys.mph
      {
         showPriceAndDayReturn("before");
         Sleep(10); // 時々４つ分移動してしまうため
         ChartNavigate(0,CHART_CURRENT_POS,+3); //CHART_CURRENT_POSは現在表示されているチャートの右端のバ        
         if(ObjectFind(0,"AnchorVLine")!=1) VLineCreate(CURR_POS_TIME);//VLineが消えた場合の対応策 
      }
    
    
    if((int)lparam == VK_UP)
    { 
      if(LOT_SELL_TOTAL==0)
      {
         if(MessageBox("Buy " + DoubleToString(InpLotSize,2) + " Lot?","新規注文",MB_OKCANCEL) != IDCANCEL) // OKが押された場合の処理。キャンセルや×ボタン押下は無視
         {
            LOT_BUY_TOTAL += 1;
            LOT_BUY_HISTORICAL_TOTAL +=1; //決済によってリセットされないヒストリカルロット数    
            ENTRY_CLOSE_PRICE = iClose(_Symbol,_Period,CURR_BAR_INDEX); 
            entryPriceArray.Add(ENTRY_CLOSE_PRICE); 
            EntryHLineCreate("buy");//ENTRY_CLOSE_PRICEの後に呼び出される必要がある
            printf("%s, buy %s lot, total lot buy: %d, Entry price: %lf",  TimeToString(CURR_POS_TIME,TIME_DATE),DoubleToString(InpLotSize,2),LOT_BUY_TOTAL,ENTRY_CLOSE_PRICE);
            EntryArrowCreate("buy");//ENTRY_CLOSE_PRICEの後に呼び出される必要がある
            ChartRedraw();
         }
      }    
    }
    
    if((int)lparam == VK_DOWN)
    { 
      if(LOT_BUY_TOTAL==0)
      {
         if(MessageBox("Sell " + DoubleToString(InpLotSize,2) + " Lot?","新規注文",MB_OKCANCEL) != IDCANCEL)// OKが押された場合の処理。キャンセルや×ボタン押下は無視
         {
            LOT_SELL_TOTAL += 1;
            LOT_SELL_HISTORICAL_TOTAL +=1; //決済によってリセットされないヒストリカルロット数 
            ENTRY_CLOSE_PRICE = iClose(_Symbol,_Period,CURR_BAR_INDEX); 
            entryPriceArray.Add(ENTRY_CLOSE_PRICE);
            EntryHLineCreate("sell");//ENTRY_CLOSE_PRICEの後に呼び出される必要がある
            printf("%s, sell %s lot, total lot sell: %d, Entry price: %lf", TimeToString(CURR_POS_TIME,TIME_DATE),DoubleToString(InpLotSize,2), LOT_SELL_TOTAL,ENTRY_CLOSE_PRICE);
            EntryArrowCreate("sell");//ENTRY_CLOSE_PRICEの後に呼び出される必要がある
            ChartRedraw();
         }  
      }    
    }
     
    if((int)lparam == VK_RETURN)
    {
      keybd_event(VK_RETURN,0,0,0);
      if(LOT_SELL_TOTAL!=0) //売りポジを持っていたら決済する
      {     
         if(MessageBox("全ての売りポジションを手仕舞いますか？\n\n保有Lot数： " + IntegerToString(LOT_SELL_TOTAL),"決済",MB_OKCANCEL) != IDCANCEL) // OKが押された場合の処理。キャンセルや×ボタン押下は無視
         {   
            MONEY += TOTAL_RETURN_SELL;
            COUNT_CLOSED +=1;
            printf("%s, Closed %d sell lot, total profit: %s, MONEY: %s Yen",TimeToString(CURR_POS_TIME,TIME_DATE),LOT_SELL_TOTAL,DoubleToString(TOTAL_RETURN_SELL,0),DoubleToString(MONEY,0));
            HLineDelete();// must be called before set lot_sell_toal to 0 
            LOT_SELL_TOTAL = 0;           
            TOTAL_RETURN_SELL=0.0;
            ClosedSignCreate("closeSellPosition");
            Comment(StringFormat("%s\nClose Price: %lf\nReturn: %s\nMoney: %s Yen",TimeToString(CURR_POS_TIME,TIME_DATE),CURR_CLOSE_PRICE,DoubleToString(TOTAL_RETURN_SELL,0),DoubleToString(MONEY,0)));
            entryPriceArray.Shutdown();            
            ChartRedraw();
            keybd_event(VK_RETURN,0,0,0);
         }
      }
      else if(LOT_BUY_TOTAL !=0) //買いポジを持っていたら決済する
      {     
         if(MessageBox("全ての買いポジションを手仕舞いますか？\n\n保有Lot数： " + IntegerToString(LOT_BUY_TOTAL),"決済",MB_OKCANCEL) != IDCANCEL) // OKが押された場合の処理。キャンセルや×ボタン押下は無視
         {   
            MONEY += TOTAL_RETURN_BUY;
            COUNT_CLOSED +=1;
            printf("%s, Closed %d buy lot, total profit: %s, money: %s Yen",TimeToString(CURR_POS_TIME,TIME_DATE),LOT_BUY_TOTAL,DoubleToString(TOTAL_RETURN_BUY,0),DoubleToString(MONEY,0));
            HLineDelete(); // must be called before set lot_buy_toal to 0 
            LOT_BUY_TOTAL = 0;
            TOTAL_RETURN_BUY=0.0;
            ClosedSignCreate("closeBuyPosition");
            Comment(StringFormat("%s\nClose Price: %lf\nReturn: %s\nMoney: %s Yen",TimeToString(CURR_POS_TIME,TIME_DATE),CURR_CLOSE_PRICE,DoubleToString(TOTAL_RETURN_BUY,0),DoubleToString(MONEY,0)));
            entryPriceArray.Shutdown();
            ChartRedraw();
            keybd_event(VK_RETURN,0,0,0);
         }
      }
    }
    }
  }
//+------------------------------------------------------------------+

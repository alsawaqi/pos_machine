package com.cpoc.softpostest;

public class Constants {




    public static final String USERNAME = BuildConfig.username;
    public static final String PASSWORD = BuildConfig.pin;

    public static final String SOFTPOS_PACKAGE_NAME_MOSAMBEE = BuildConfig.target_package_name;

    public static final int ActivityLoginRequestCode = 100;
    public static final int ActivityHealthCheckRequestCode = 101;
    public static final int ActivityPaymentRequestCode = 102;
    public static final int ActivityDetailsRequestCode = 103;

    public static final int ActivityLogsRequestCode = 104;
    public static final int ActivityLastReceiptRequestCode = 105;


    public static final int ActivityRefundRequestCode = 106;
    public static final int ActivityVoidRequestCode = 107;

    public static final int ActivitySettlementRequestCode = 108;
    public static final int ActivityLastTransactionsRequestCode = 109;

    public static final int ActivityAppUpdateRequestCode = 110;

    public static final int ActivityPreauthRequestCode = 111;
    public static final int ActivitySalecompleteRequestCode = 112;


//    public static final String SOFTPOS_PACKAGE_NAME_MOSAMBEE = "com.mosambee.mpos.mobile2i";
//    public static final String SOFTPOS_PACKAGE_NAME_MOSAMBEE = "com.mosambee.softpos";
//    public static final String SOFTPOS_PACKAGE_NAME_MOSAMBEE = "com.mosambee.dhofar.softpos";


    public static final String SOFTPOS_REFUND_DHOFAR_ACTION ="com.mosambee.softpos.refund.dhofar";

    public static final String SOFTPOS_INIT_ACTION = "com.mosambee.softpos.login";
    public static final String SOFTPOS_PAYMENT_ACTION = "com.mosambee.softpos.payment";
    public static final String SOFTPOS_PREAUTH_ACTION = "com.mosambee.softpos.preauth";
    public static final String SOFTPOS_SALECOMPLETE_ACTION = "com.mosambee.softpos.salecomplete";

    public static final String SOFTPOS_HEALTHCHECK_ACTION = "com.mosambee.softpos.healthcheck";
    public static final String SOFTPOS_DETAILS_ACTION = "com.mosambee.softpos.details";
    public static final String SOFTPOS_LAST_TRANSACTION_ACTION = "com.mosambee.softpos.last.transaction";
    public static final String SOFTPOS_VOID_ACTION = "com.mosambee.softpos.void";
    public static final String SOFTPOS_LAST_TRANSACTIONS_ACTION = "com.mosambee.softpos.lasttransactions";
    public static final String SOFTPOS_SETTLEMENT_ACTION = "com.mosambee.softpos.settlement";
    public static final String SOFTPOS_REFUND_ACTION = "com.mosambee.softpos.refund";
    public static final String SOFTPOS_TXN_REFUND_ACTION ="com.mosambee.softpos.txn.refund";

    public static final String SOFTPOS_APP_UPDATE = "com.mosambee.softpos.appupdate";


    public static final String SOFTPOS_ADD_MONEY_CASH_ACTION = "com.mosambee.softpos.addMoneyCash";
    public static final String SOFTPOS_ADD_MONEY_ACCOUNT_ACTION = "com.mosambee.softpos.addMoneyAccount";

    public static final String SOFTPOS_BALANCE_UPDATE_ACTION = "com.mosambee.softpos.balanceUpdate";
    public static final String SOFTPOS_BALANCE_ENQUIRY_ACTION = "com.mosambee.softpos.balanceEnquiry";

}

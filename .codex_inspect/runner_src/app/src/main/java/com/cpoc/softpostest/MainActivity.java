package com.cpoc.softpostest;


import android.app.AlertDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.nfc.NfcAdapter;
import android.os.AsyncTask;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.EditText;
import android.widget.Toast;


import androidx.appcompat.app.AppCompatActivity;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.google.gson.JsonSyntaxException;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.List;


public class MainActivity extends AppCompatActivity {


    EditText etUserId, eTPass, etAmount, eTTxnId,eTCheckStatusId;

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    String userId;
    String password;

    private ApiType apiType;

    public ApiType getApiType() {
        return apiType;
    }

    public void setApiType(ApiType apiType) {
        this.apiType = apiType;
    }

//    public void pay(View view) {
//
//        if (isMosambeeExist){
//            setApiType(ApiType.PAYMENT);
//
//            new TestAsync().execute();
//        }else{
//            new AlertDialog.Builder(MainActivity.this)
//                    .setTitle("Message")
//                    .setMessage("This Application require Mosambee App in a Device")
//                    .setPositiveButton("OK", null)
//                    .show();
//
//        }
//
//
//
//    }



    boolean isMosambeeExist = false;

    boolean isPaytmAppExist = false;


//    private NfcHelper nfcHelper;
    private NfcAdapter nfcAdapter;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_mosambee);

        etUserId = findViewById(R.id.eTuserId);

        eTPass = findViewById(R.id.eTPass);

        etAmount = findViewById(R.id.eTAmount);


        eTCheckStatusId = findViewById(R.id.eTCheckStatusId);




        eTTxnId = findViewById(R.id.eTTxnId);





        etUserId.setText(Constants.USERNAME);

        eTPass.setText(Constants.PASSWORD);

        etAmount.setText("100");

        isMosambeeExist = isMosambeeAppExist();

        isPaytmAppExist = isPaytmAppExist();

        Log.i("isMosambeeExist", isMosambeeExist + "");

        Log.i("isPaytmAppExist", isPaytmAppExist + "");


//        nfcHelper = new NfcHelper();
//        nfcAdapter = NfcAdapter.getDefaultAdapter(this);
//        nfcHelper.setupNfcAdapter(nfcAdapter, this);


    }


    public void pay(View view) {

        setApiType(ApiType.PAYMENT);

//        setApiType(ApiType.PREAUTH);

        new TestAsync().execute();

    }


    public void healthCheck(View view) {
        setApiType(ApiType.HEALTH);
        new TestAsync().execute();

    }



    public void bTinitApi(View view) {

        setApiType(ApiType.LOGIN);
        new TestAsync().execute();

    }

    public void txnRefund(View view) {

        setApiType(ApiType.TXNREFUND);

//        setApiType(ApiType.SALECOMPLETE);

        new TestAsync().execute();
    }

    public void refundDhofar(View view) {
        setApiType(ApiType.DHOFARREFUND);

        new TestAsync().execute();
    }


    public void payVoid(View view) {

        setApiType(ApiType.VOID);

        new TestAsync().execute();
    }

    public void paySettlement(View view) {
        setApiType(ApiType.SETTLEMENT);

        new TestAsync().execute();
    }

    public void payLastTransactions(View view) {
        setApiType(ApiType.LAST_TRANSACTIONS);

        new TestAsync().execute();
    }


    public void getDetailsMosambee(View view) {
        setApiType(ApiType.DETAILS);
        new TestAsync().execute();
    }


    public void getDetails(View view) {
        setApiType(ApiType.DETAILS);
        new TestAsync().execute();
    }



    public void uploadLogs(View view) {
        setApiType(ApiType.CRASHLOGS);
        new TestAsync().execute();
    }


    public void getLastReceipt(View view) {


        setApiType(ApiType.LASTRECEIPT);
        new TestAsync().execute();

    }


    public void balanceEnquiry(View view) {
        setApiType(ApiType.BALANCEENQUIRY);
        new TestAsync().execute();

    }

    public void balanceUpdate(View view) {
        setApiType(ApiType.BALANCEUPDATE);
        new TestAsync().execute();

    }

    public void softPOSAppUpdate(View view) {
        setApiType(ApiType.APPUPDATE);
        new TestAsync().execute();

    }

    public void addMoneyCash(View view) {
        setApiType(ApiType.ADDMONEYCASH);
        new TestAsync().execute();

    }

    public void addMoneyAccount(View view) {
        setApiType(ApiType.ADDMONEYACCOUNT);
        new TestAsync().execute();

    }




    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (data!=null) {
            boolean result = data.getBooleanExtra("result", false);
            String reason = data.getStringExtra("reason");
            String transactionId = data.getStringExtra("transactionId");
            String transactionData = data.getStringExtra("transactionData");
            String amount = data.getStringExtra("amount");
            String reasonCode = data.getStringExtra("reasonCode");

            // Create a message to display in the AlertDialog
            String message = "Result: " + result + "\n" +
                    "Reason: " + reason + "\n" +
                    "Transaction ID: " + transactionId + "\n" +
                    "Transaction Data: " + transactionData + "\n" +
                    "Amount: " + amount + "\n" +
                    "Reason Code: " + reasonCode;

            // Show the AlertDialog with the returned data
            new AlertDialog.Builder(this)
                    .setTitle("Transaction Details")
                    .setMessage(message)
                    .setPositiveButton("OK", new DialogInterface.OnClickListener() {
                        @Override
                        public void onClick(DialogInterface dialog, int which) {
                            dialog.dismiss();
                        }
                    })
                    .show();
        }
    }


    boolean isMosambeeAppExist(){
        final PackageManager pm = getPackageManager();
        List<ApplicationInfo> packages = pm.getInstalledApplications(PackageManager.GET_META_DATA);

        for (ApplicationInfo packageInfo : packages) {


            if (packageInfo.packageName.contains(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE)) {
                return true;
            }
        }
return false;
    }

    boolean isPaytmAppExist(){
        final PackageManager pm = getPackageManager();
        List<ApplicationInfo> packages = pm.getInstalledApplications(PackageManager.GET_META_DATA);

        for (ApplicationInfo packageInfo : packages) {


            if (packageInfo.packageName.contains(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE)) {
                return true;
            }
        }
        return false;
    }

    public void updateApp(View view) {
    }



    enum ApiType {LOGIN, REFUND, HEALTH, PAYMENT, TXNREFUND, DETAILS, CRASHLOGS, LASTRECEIPT, VOID, SETTLEMENT, BALANCEENQUIRY, ADDMONEYACCOUNT, ADDMONEYCASH, BALANCEUPDATE, LAST_TRANSACTIONS, APPUPDATE, PREAUTH, SALECOMPLETE, DHOFARREFUND}

    class TestAsync extends AsyncTask<Void, Integer, Boolean> {
        String TAG = getClass().getSimpleName();

        protected Boolean doInBackground(Void... arg0) {

            return true;
        }

        protected void onPostExecute(Boolean result) {
            super.onPostExecute(result);
            if (!result) {

                new AlertDialog.Builder(MainActivity.this)
                        .setTitle("Message")
                        .setMessage("This Application require Mosambee SoftPOS in a Device")
                        .setPositiveButton("OK", null)
                        .show();

            } else {

                if (getApiType().equals(ApiType.PAYMENT)) {

                    if ((etAmount.getText().toString() != "")) {




                        int am = 0;

                        try {
                            am = Integer.parseInt(etAmount.getText().toString());

                        } catch (NumberFormatException e) {
                            Toast.makeText(MainActivity.this, "Not a valid integer", Toast.LENGTH_LONG).show();
                            return;
                        }

                        Intent intent = new Intent();
                        intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                        Bundle mBundle = new Bundle();
                        mBundle.putString("amount", String.format("%d", am));
//                        mBundle.putString("sessionId", Utils.getToken(MainActivity.this));
//                        mBundle.putString("mobNo", "8424834651");
//                        mBundle.putString("description", eTCheckStatusId.getText().toString());



                        intent.putExtras(mBundle);
                        intent.setAction(Constants.SOFTPOS_PAYMENT_ACTION);
                        startActivityForResult(intent, Constants.ActivityPaymentRequestCode);
                    } else {
                        Toast.makeText(MainActivity.this, "Amount can not be black", Toast.LENGTH_LONG).show();
                    }
                }else if (getApiType().equals(ApiType.PREAUTH)) {

                    if ((etAmount.getText().toString() != "")) {




                        int am = 0;

                        try {
                            am = Integer.parseInt(etAmount.getText().toString());

                        } catch (NumberFormatException e) {
                            Toast.makeText(MainActivity.this, "Not a valid integer", Toast.LENGTH_LONG).show();
                            return;
                        }

                        Intent intent = new Intent();
                        intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                        Bundle mBundle = new Bundle();
                        mBundle.putString("amount", String.format("%d", am));
                        mBundle.putString("sessionId", Utils.getToken(MainActivity.this));
                        mBundle.putString("mobNo", "8424834651");
                        mBundle.putString("description", eTCheckStatusId.getText().toString());

                        intent.putExtras(mBundle);
                        intent.setAction(Constants.SOFTPOS_PREAUTH_ACTION);
                        startActivityForResult(intent, Constants.ActivityPreauthRequestCode);
                    } else {
                        Toast.makeText(MainActivity.this, "Amount can not be black", Toast.LENGTH_LONG).show();
                    }
                } else if (getApiType().equals(ApiType.BALANCEENQUIRY)) {

                    if ((etAmount.getText().toString() != "")) {

                        int am = 0;

                        try {
                            am = Integer.parseInt(etAmount.getText().toString());

                        } catch (NumberFormatException e) {
                            Toast.makeText(MainActivity.this, "Not a valid integer", Toast.LENGTH_LONG).show();
                            return;
                        }

                        Intent intent = new Intent();
                        intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                        Bundle mBundle = new Bundle();
                        mBundle.putString("amount", String.format("%d", am));
                        mBundle.putString("sessionId", Utils.getToken(MainActivity.this));
                        mBundle.putString("mobNo", "8424834651");
                        mBundle.putString("description", eTCheckStatusId.getText().toString());

                        intent.putExtras(mBundle);
                        intent.setAction(Constants.SOFTPOS_BALANCE_ENQUIRY_ACTION);
                        startActivityForResult(intent, Constants.ActivityPaymentRequestCode);
                    } else {
                        Toast.makeText(MainActivity.this, "Amount can not be black", Toast.LENGTH_LONG).show();
                    }
                } else if (getApiType().equals(ApiType.BALANCEUPDATE)) {

                    if ((etAmount.getText().toString() != "")) {

                        int am = 0;

                        try {
                            am = Integer.parseInt(etAmount.getText().toString());

                        } catch (NumberFormatException e) {
                            Toast.makeText(MainActivity.this, "Not a valid integer", Toast.LENGTH_LONG).show();
                            return;
                        }

                        Intent intent = new Intent();
                        intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                        Bundle mBundle = new Bundle();
                        mBundle.putString("amount", String.format("%d", am));
                        mBundle.putString("sessionId", Utils.getToken(MainActivity.this));
                        mBundle.putString("mobNo", "8424834651");
                        mBundle.putString("description", eTCheckStatusId.getText().toString());

                        intent.putExtras(mBundle);
                        intent.setAction(Constants.SOFTPOS_BALANCE_UPDATE_ACTION);
                        startActivityForResult(intent, Constants.ActivityPaymentRequestCode);
                    } else {
                        Toast.makeText(MainActivity.this, "Amount can not be black", Toast.LENGTH_LONG).show();
                    }
                } else if (getApiType().equals(ApiType.ADDMONEYACCOUNT)) {

                    if ((etAmount.getText().toString() != "")) {

                        int am = 0;

                        try {
                            am = Integer.parseInt(etAmount.getText().toString());

                        } catch (NumberFormatException e) {
                            Toast.makeText(MainActivity.this, "Not a valid integer", Toast.LENGTH_LONG).show();
                            return;
                        }

                        Intent intent = new Intent();
                        intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                        Bundle mBundle = new Bundle();
                        mBundle.putString("amount", String.format("%d", am));
                        mBundle.putString("sessionId", Utils.getToken(MainActivity.this));
                        mBundle.putString("mobNo", "8424834651");
                        mBundle.putString("description", eTCheckStatusId.getText().toString());


                        intent.putExtras(mBundle);
                        intent.setAction(Constants.SOFTPOS_ADD_MONEY_ACCOUNT_ACTION);
                        startActivityForResult(intent, Constants.ActivityPaymentRequestCode);
                    } else {
                        Toast.makeText(MainActivity.this, "Amount can not be black", Toast.LENGTH_LONG).show();
                    }
                } else if (getApiType().equals(ApiType.ADDMONEYCASH)) {

                    if ((etAmount.getText().toString() != "")) {

                        int am = 0;

                        try {
                            am = Integer.parseInt(etAmount.getText().toString());

                        } catch (NumberFormatException e) {
                            Toast.makeText(MainActivity.this, "Not a valid integer", Toast.LENGTH_LONG).show();
                            return;
                        }

                        Intent intent = new Intent();
                        intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                        Bundle mBundle = new Bundle();
                        mBundle.putString("amount", String.format("%d", am));
                        mBundle.putString("sessionId", Utils.getToken(MainActivity.this));
                        mBundle.putString("mobNo", "8424834651");
                        mBundle.putString("description", eTCheckStatusId.getText().toString());

                        intent.putExtras(mBundle);
                        intent.setAction(Constants.SOFTPOS_ADD_MONEY_CASH_ACTION);
                        startActivityForResult(intent, Constants.ActivityPaymentRequestCode);
                    } else {
                        Toast.makeText(MainActivity.this, "Amount can not be black", Toast.LENGTH_LONG).show();
                    }
                } else if (getApiType().equals(ApiType.REFUND)) {

                    if ((etAmount.getText().toString() != "")) {

                        int am = 0;

                        try {
                            am = Integer.parseInt(etAmount.getText().toString());

                        } catch (NumberFormatException e) {
                            Toast.makeText(MainActivity.this, "Not a valid integer", Toast.LENGTH_LONG).show();
                            return;
                        }

                        Intent intent = new Intent();
                        intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                        Bundle mBundle = new Bundle();
                        mBundle.putString("amount", String.format("%d", am));
                        mBundle.putString("sessionId", Utils.getToken(MainActivity.this));
                        mBundle.putString("mobNo", "8424834651");
                        mBundle.putString("description", eTCheckStatusId.getText().toString());

                        intent.putExtras(mBundle);
                        intent.setAction(Constants.SOFTPOS_REFUND_ACTION);
                        startActivityForResult(intent, Constants.ActivityRefundRequestCode);
                    } else {
                        Toast.makeText(MainActivity.this, "Amount can not be black", Toast.LENGTH_LONG).show();
                    }
                } else if (getApiType().equals(ApiType.LOGIN)) {

                    if ((!etUserId.getText().toString().equals("")) && (!eTPass.getText().toString().equals(""))) {
                        setPassword(eTPass.getText().toString());
                        setUserId(etUserId.getText().toString());
                        PasswordToken passwordToken = new PasswordToken(getUserId(),getPassword());

                        Intent intent = new Intent();
                        Bundle mBundle = new Bundle();
                        mBundle.putString("userName", getUserId());
                        mBundle.putString("password", passwordToken.getPasswordToken());
//                        mBundle.putString("password", getPassword());
                        mBundle.putString("partnerId", "200");

                        intent.putExtras(mBundle);
                        intent.setAction(Constants.SOFTPOS_INIT_ACTION);
                        intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                        startActivityForResult(intent, Constants.ActivityLoginRequestCode);


                    }
                } else if (getApiType().equals(ApiType.HEALTH)) {

                    Intent intent = new Intent();
//                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    intent.setAction(Constants.SOFTPOS_HEALTHCHECK_ACTION);
                    intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                    Bundle bundle = new Bundle();
                    bundle.putString("sessionId", Utils.getToken(MainActivity.this));
                    intent.putExtras(bundle);
                    startActivityForResult(intent, Constants.ActivityHealthCheckRequestCode);
                } else if (getApiType().equals(ApiType.DETAILS)) {

                    Intent intent = new Intent();
//                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    intent.setAction(Constants.SOFTPOS_DETAILS_ACTION);
                    intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                    startActivityForResult(intent, Constants.ActivityDetailsRequestCode);
                }  else if (getApiType().equals(ApiType.LASTRECEIPT)) {

                    Intent intent = new Intent();
//                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    intent.setAction(Constants.SOFTPOS_LAST_TRANSACTION_ACTION);
                    intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);

                    startActivityForResult(intent, Constants.ActivityLastReceiptRequestCode);
                } else if (getApiType().equals(ApiType.VOID)) {

                    Intent intent = new Intent();
//                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    intent.setAction(Constants.SOFTPOS_VOID_ACTION);
                    intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);

                    Bundle bundle = new Bundle();
                    bundle.putString("sessionId", Utils.getToken(MainActivity.this));
                    bundle.putString("transactionId", eTTxnId.getText().toString());
                    intent.putExtras(bundle);

                    startActivityForResult(intent, Constants.ActivityVoidRequestCode);
                }else if (getApiType().equals(ApiType.SETTLEMENT)) {

                    Intent intent = new Intent();
//                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    intent.setAction(Constants.SOFTPOS_SETTLEMENT_ACTION);
                    intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);

                    Bundle bundle = new Bundle();
                    bundle.putString("sessionId", Utils.getToken(MainActivity.this));
                    intent.putExtras(bundle);

                    startActivityForResult(intent, Constants.ActivitySettlementRequestCode);
                }else if (getApiType().equals(ApiType.APPUPDATE)) {

                    Intent intent = new Intent();
//                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    intent.setAction(Constants.SOFTPOS_APP_UPDATE);
                    intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);
                    Bundle bundle = new Bundle();
                    bundle.putString("sessionId", Utils.getToken(MainActivity.this));
                    intent.putExtras(bundle);

                    startActivityForResult(intent, Constants.ActivityAppUpdateRequestCode);
                }  else if (getApiType().equals(ApiType.LAST_TRANSACTIONS)) {

                    Intent intent = new Intent();
//                    intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP);
                    intent.setAction(Constants.SOFTPOS_LAST_TRANSACTIONS_ACTION);
                    intent.setPackage(Constants.SOFTPOS_PACKAGE_NAME_MOSAMBEE);

                    Bundle bundle = new Bundle();
                    bundle.putString("sessionId", Utils.getToken(MainActivity.this));
                    bundle.putString("count", "0");
                    bundle.putString("txnType", "0");
                    bundle.putString("txnStatus", "0");

                    intent.putExtras(bundle);

                    startActivityForResult(intent, Constants.ActivityLastTransactionsRequestCode);
                }
            }
        }
    }

}
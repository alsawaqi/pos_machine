package com.cpoc.softpostest;

import android.content.Context;
import android.content.SharedPreferences;
import android.preference.PreferenceManager;

import org.json.JSONException;
import org.json.JSONObject;

public class Utils {

    public static final String PREF_SESSIONID = "sessionId";




    public static void setToken(Context context, String token) {
        SharedPreferences.Editor editor = getSharedPreferences(context).edit();
        editor.putString(PREF_SESSIONID, token);
        editor.apply();
        editor.commit();
    }


    public static String getToken(Context context) {
        return getSharedPreferences(context).getString(PREF_SESSIONID, null);
    }


    static SharedPreferences getSharedPreferences(Context ctx) {
        return PreferenceManager.getDefaultSharedPreferences(ctx);
    }

    public static String getJsonValue(JSONObject jsonObject, String key) {
        String value = "NA";
        try {
            if (jsonObject != null && jsonObject.has(key))
                value = jsonObject.getString(key);
        } catch (JSONException je) {
            je.printStackTrace();
        }
        return value;
    }

}

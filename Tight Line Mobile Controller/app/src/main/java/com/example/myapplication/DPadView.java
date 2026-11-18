package com.example.myapplication;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.os.Handler;
import android.os.Looper;
import android.util.AttributeSet;
import android.view.MotionEvent;
import android.view.View;

public class DPadView extends View {

    public interface OnMoveListener {
        void onMove(float x, float y);
    }

    private OnMoveListener listener;

    private final Paint basePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint activePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint arrowPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

    private float currentX = 0f;
    private float currentY = 0f;
    private boolean isPressed = false;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private static final long STREAM_INTERVAL_MS = 50L;

    private final Runnable streamRunnable = new Runnable() {
        @Override
        public void run() {
            if (isPressed && listener != null) {
                listener.onMove(currentX, currentY);
                handler.postDelayed(this, STREAM_INTERVAL_MS);
            }
        }
    };

    public DPadView(Context context, AttributeSet attrs) {
        super(context, attrs);
        init();
    }

    private void init() {
        basePaint.setColor(Color.parseColor("#2A2D3E"));
        basePaint.setStyle(Paint.Style.FILL);

        activePaint.setColor(Color.parseColor("#4A4E69"));
        activePaint.setStyle(Paint.Style.FILL);

        arrowPaint.setColor(Color.parseColor("#F2E9E4"));
        arrowPaint.setStyle(Paint.Style.FILL);
    }

    public void setOnMoveListener(OnMoveListener listener) {
        this.listener = listener;
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);

        float cx = getWidth() / 2f;
        float cy = getHeight() / 2f;
        float radius = Math.min(cx, cy) - 10f;

        // Base circle / D-pad outline
        canvas.drawCircle(cx, cy, radius, basePaint);

        // Highlight active direction
        if (isPressed && (currentX != 0f || currentY != 0f)) {
            canvas.drawCircle(cx + currentX * radius * 0.4f, cy + currentY * radius * 0.4f, radius * 0.4f, activePaint);
        }

        // Draw directional arrows
        float arrowSize = radius * 0.2f;
        drawArrow(canvas, cx, cy - radius * 0.65f, arrowSize, 0);   // UP
        drawArrow(canvas, cx + radius * 0.65f, cy, arrowSize, 90);  // RIGHT
        drawArrow(canvas, cx, cy + radius * 0.65f, arrowSize, 180); // DOWN
        drawArrow(canvas, cx - radius * 0.65f, cy, arrowSize, 270); // LEFT
    }

    private void drawArrow(Canvas canvas, float cx, float cy, float size, float angleDeg) {
        canvas.save();
        canvas.rotate(angleDeg, cx, cy);

        Path path = new Path();
        path.moveTo(cx, cy - size);
        path.lineTo(cx - size * 0.7f, cy + size * 0.5f);
        path.lineTo(cx + size * 0.7f, cy + size * 0.5f);
        path.close();

        canvas.drawPath(path, arrowPaint);
        canvas.restore();
    }

    @Override
    public boolean onTouchEvent(MotionEvent event) {
        float cx = getWidth() / 2f;
        float cy = getHeight() / 2f;
        float dx = event.getX() - cx;
        float dy = event.getY() - cy;

        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_MOVE: {
                isPressed = true;
                getParent().requestDisallowInterceptTouchEvent(true);

                float radius = Math.min(cx, cy);
                float normX = dx / radius;
                float normY = dy / radius;

                // Deadzone check
                float mag = (float) Math.hypot(normX, normY);
                if (mag < 0.15f) {
                    normX = 0f;
                    normY = 0f;
                } else if (mag > 1.0f) {
                    normX /= mag;
                    normY /= mag;
                }

                // Discretize to 8 directions or continuous vector
                currentX = normX;
                currentY = normY;

                invalidate();

                if (listener != null) {
                    listener.onMove(currentX, currentY);
                }

                handler.removeCallbacks(streamRunnable);
                handler.postDelayed(streamRunnable, STREAM_INTERVAL_MS);
                return true;
            }

            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL: {
                isPressed = false;
                currentX = 0f;
                currentY = 0f;
                invalidate();

                handler.removeCallbacks(streamRunnable);
                if (listener != null) {
                    listener.onMove(0f, 0f);
                }
                return true;
            }
        }
        return super.onTouchEvent(event);
    }
}
